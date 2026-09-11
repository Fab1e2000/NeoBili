import Foundation
import Observation

typealias LiveRoomLoader = @Sendable (Int) async throws -> LiveRoom
typealias LivePlaybackLoader = @Sendable (Int, Int) async throws -> LivePlayback

/// 直播不复用点播的进度、心跳与历史记录；只共享稳定的 mpv 渲染内核。
@MainActor
@Observable
final class LivePlayerModel {
    private(set) var room: LiveRoom
    private(set) var session: MPVPlayerSession
    private(set) var isLoading = true
    private(set) var isBuffering = false
    private(set) var isPlaying = false
    private(set) var isOffline = false
    private(set) var hasRenderedFirstFrame = false
    private(set) var errorMessage: String?
    private(set) var displayAspectRatio: Double?
    private(set) var qualities: [LiveQuality] = []
    private(set) var selectedQuality: Int = 10000

    private let roomLoader: LiveRoomLoader
    private let playbackLoader: LivePlaybackLoader
    private let sourceOpener: PlaybackSourceOpener
    private let publishesSystemMedia: Bool
    private let startupTimeout: Duration
    private let mediaSessionID = UUID()
    private var generation = 0
    private var engineID = UUID()
    private var candidates: [LiveStreamCandidate] = []
    private var candidateIndex = 0
    private var isStopped = false
    private var wantsPlayback = true
    private var recovering = false
    private var metadataTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var canUsePreparedSession = true
    private var playbackRoomID: Int
    private var timeoutTask: Task<Void, Never>?

    init(room: LiveRoom,
         roomLoader: @escaping LiveRoomLoader = { try await LiveAPI.roomInfo(roomID: $0) },
         playbackLoader: @escaping LivePlaybackLoader = { try await LiveAPI.playback(roomID: $0, quality: $1) },
         sourceOpener: @escaping PlaybackSourceOpener = { session, source, _ in try await session.open(source: source) },
         publishesSystemMedia: Bool = true,
         startupTimeout: Duration = .seconds(10)) {
        self.room = room
        self.roomLoader = roomLoader
        self.playbackLoader = playbackLoader
        self.sourceOpener = sourceOpener
        self.publishesSystemMedia = publishesSystemMedia
        self.startupTimeout = startupTimeout
        playbackRoomID = room.roomID
        session = MPVPlayerSession(configuration: .live(roomID: room.roomID))
    }

    deinit {
        MainActor.assumeIsolated {
            metadataTask?.cancel()
            recoveryTask?.cancel()
            timeoutTask?.cancel()
            session.onEvent = nil
            session.stop()
            if publishesSystemMedia { SystemNowPlayingCenter.shared.deactivate(sessionID: mediaSessionID) }
        }
    }

    func load(quality: Int? = nil) async {
        guard !isStopped else { return }
        generation += 1
        let request = generation
        metadataTask?.cancel()
        recoveryTask?.cancel()
        timeoutTask?.cancel()
        engineID = UUID()
        session.onEvent = nil
        session.pause()
        isPlaying = false
        isLoading = true
        isBuffering = false
        hasRenderedFirstFrame = false
        isOffline = false
        errorMessage = nil
        recovering = false
        // PiliPlus 的 queryLiveUrl 与 queryLiveInfoH5 并行：主播资料不是取流前置条件。
        // 播放接口本身返回权威开播状态、规范房间号；慢资料请求不应挡住首帧。
        let requestedRoomID = room.roomID
        metadataTask = Task { [weak self, roomLoader] in
            do {
                let updatedRoom = try await roomLoader(requestedRoomID)
                guard let self, self.isCurrent(request) else { return }
                self.room = updatedRoom
                if !self.qualities.isEmpty, !self.isOffline, self.errorMessage == nil {
                    self.activateSystemMedia()
                    self.publishPlaybackState()
                }
            } catch {
                // 资料加载失败不关闭已获得的合法直播流，也不重试受限请求。
            }
        }
        do {
            let playback = try await playbackLoader(requestedRoomID, quality ?? selectedQuality)
            guard isCurrent(request) else { return }
            guard playback.isLive else {
                isOffline = true
                isLoading = false
                session.stop()
                canUsePreparedSession = false
                if publishesSystemMedia { SystemNowPlayingCenter.shared.deactivate(sessionID: mediaSessionID) }
                return
            }
            qualities = playback.qualities
            // 只尝试有限个服务器返回的地址，失败后由用户重新连接。
            candidates = LiveStreamStartupPolicy.candidates(from: playback.candidates)
            playbackRoomID = playback.roomID
            candidateIndex = 0
            guard let first = candidates.first else { throw PlayerSessionError.invalidSource }
            selectedQuality = first.quality
            if playback.isPortrait, displayAspectRatio == nil { displayAspectRatio = 9.0 / 16 }
            activateSystemMedia()
            await openCandidate(request: request)
        } catch {
            guard isCurrent(request), !error.isCancellation else { return }
            fail(error.localizedDescription)
        }
    }

    func togglePlayback() { isPlaying || wantsPlayback && isLoading ? pause() : play() }

    func play() {
        guard !isStopped, !isOffline, errorMessage == nil else { return }
        wantsPlayback = true
        session.play()
        if hasRenderedFirstFrame { isPlaying = true }
        publishPlaybackState()
    }

    func pause() {
        wantsPlayback = false
        session.pause()
        isPlaying = false
        publishPlaybackState()
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        generation += 1
        timeoutTask?.cancel()
        metadataTask?.cancel()
        recoveryTask?.cancel()
        session.onEvent = nil
        session.stop()
        isPlaying = false
        if publishesSystemMedia { SystemNowPlayingCenter.shared.deactivate(sessionID: mediaSessionID) }
    }

    private func openCandidate(request: Int) async {
        guard isCurrent(request), candidates.indices.contains(candidateIndex) else { return }
        timeoutTask?.cancel()
        let candidate = candidates[candidateIndex]
        selectedQuality = candidate.quality
        let nextID = UUID()
        engineID = nextID
        session.onEvent = nil
        // 页面挂载时已预热首个内核，不在地址返回时白白销毁再初始化 Metal/mpv。
        // 换清晰度与失败恢复仍使用独立内核，隔离旧事件与旧 opener 的迟到回调。
        let next: MPVPlayerSession
        if canUsePreparedSession {
            canUsePreparedSession = false
            next = session
        } else {
            session.stop()
            next = MPVPlayerSession(configuration: .live(roomID: playbackRoomID))
            session = next
        }
        isLoading = true
        hasRenderedFirstFrame = false
        isBuffering = false
        next.onEvent = { [weak self] event in
            guard let self, self.engineID == nextID, self.isCurrent(request) else { return }
            self.receive(event)
        }
        recovering = false
        let source = PlaybackSource(video: PlaybackStream(primary: candidate.url, backups: []), audio: nil, duration: 0)
        timeoutTask = Task { [weak self, startupTimeout] in
            try? await Task.sleep(for: startupTimeout)
            guard !Task.isCancelled, let self, self.isCurrent(request), self.engineID == nextID,
                  !self.hasRenderedFirstFrame else { return }
            self.recoverOrFail("直播连接超时，请重新连接")
        }
        do {
            try await sourceOpener(next, source, 0)
        } catch {
            // 同一请求内也会更换内核：旧 opener 迟到的失败不能关闭新候选。
            guard isCurrent(request), engineID == nextID else { return }
            if !error.isCancellation { recoverOrFail(error.localizedDescription) }
            return
        }
        guard isCurrent(request), engineID == nextID else { return }
        if wantsPlayback { next.play() } else { next.pause() }
    }

    /// 事件不包含历史进度：直播时间轴不能当作点播位置保存或跳转。
    func receive(_ event: PlayerPlaybackEvent) {
        guard !isStopped else { return }
        switch event {
        case .firstFrame:
            timeoutTask?.cancel()
            hasRenderedFirstFrame = true
            isLoading = false
            isPlaying = wantsPlayback
            errorMessage = nil
            if !wantsPlayback { session.pause() }
            publishPlaybackState()
        case .playing(let playing):
            if hasRenderedFirstFrame { isPlaying = playing && wantsPlayback; publishPlaybackState() }
        case .buffering(let buffering): isBuffering = buffering
        case .displayAspectRatio(let ratio):
            if ratio.isFinite, ratio > 0 { displayAspectRatio = ratio }
        case .error(let message): recoverOrFail(message)
        case .ended: recoverOrFail("直播连接已结束，请重新连接")
        default: break
        }
    }

    private func recoverOrFail(_ message: String) {
        guard !isStopped, !recovering else { return }
        timeoutTask?.cancel()
        guard candidateIndex + 1 < candidates.count else { fail(message); return }
        candidateIndex += 1
        recovering = true
        engineID = UUID()
        session.onEvent = nil
        session.stop()
        let request = generation
        recoveryTask = Task { [weak self] in
            guard let self, self.isCurrent(request) else { return }
            await self.openCandidate(request: request)
        }
    }

    private func fail(_ message: String) {
        timeoutTask?.cancel()
        engineID = UUID()
        isLoading = false
        isBuffering = false
        isPlaying = false
        errorMessage = message
        canUsePreparedSession = false
        session.onEvent = nil
        session.stop()
        publishPlaybackState()
    }

    private func isCurrent(_ request: Int) -> Bool { !isStopped && generation == request && !Task.isCancelled }

    private func activateSystemMedia() {
        guard publishesSystemMedia else { return }
        SystemNowPlayingCenter.shared.activate(
            sessionID: mediaSessionID,
            metadata: SystemMediaMetadata(identifier: "live:\(room.roomID)", title: room.title,
                                          artist: room.username, artworkURL: room.coverURL, isLiveStream: true),
            onPlay: { [weak self] in self?.play() }, onPause: { [weak self] in self?.pause() },
            onToggle: { [weak self] in self?.togglePlayback() }, onSeek: { _ in }
        )
    }

    private func publishPlaybackState() {
        guard publishesSystemMedia else { return }
        SystemNowPlayingCenter.shared.updatePlaybackState(isPlaying: isPlaying, sessionID: mediaSessionID)
    }
}
