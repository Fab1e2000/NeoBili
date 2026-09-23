import Foundation
import SwiftUI

typealias PlaybackURLLoader = @Sendable (String, Int) async throws -> PlayURLData
typealias QualityPlaybackURLLoader = @Sendable (String, Int, Int) async throws -> PlayURLData
typealias PlaybackSourceOpener = @MainActor (MPVPlayerSession, PlaybackSource, TimeInterval) async throws -> Void

@MainActor
@Observable
final class PlayerViewModel {
    let storyboardStore = VideoStoryboardStore()
    let bvid: String
    let cid: Int
    private(set) var configuration: VideoPlaybackConfiguration
    private(set) var session: MPVPlayerSession
    /// 弹幕控制器与播放器同生命周期；开关打开时由界面触发创建。
    private(set) var danmaku: DanmakuController?

    private(set) var isLoading = true
    private(set) var errorMessage: String?
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    /// 已经缓冲到的位置，进度条用它画出比播放位置更靠前的浅色区段。
    private(set) var bufferedTime: Double = 0
    private(set) var hasRenderedFirstFrame = false
    private(set) var displayAspectRatio: Double?
    private(set) var decodedVideoWidth: Int?
    private(set) var decodedVideoHeight: Int?
    private(set) var selectedVideoWidth: Int?
    private(set) var selectedVideoHeight: Int?
    private var hasDecodedAspectRatio = false

    private var playbackPayload: PlayURLData?
    private(set) var isSwitchingQuality = false

    var availableVideoQualities: [Int] { playbackPayload?.declaredVideoQualities ?? [] }

    var availableAudioQualities: [Int] {
        Array(Set(playbackPayload?.dash?.allAudio.filter { URL(string: $0.baseUrl) != nil }.map(\.id) ?? []))
            .sorted { PlaybackQuality.audioRank($0) > PlaybackQuality.audioRank($1) }
    }

    private(set) var selectedVideoQuality: Int?
    private(set) var selectedAudioQuality: Int?
    private var qualityRequestID = UUID()
    private var qualityFetchTask: Task<PlayURLData, Error>?
    private var isFetchingQuality = false
    /// 换源期间保留最后一次播放/暂停意图，防止新内核默认播放覆盖用户暂停。
    private var qualityPlaybackIntent: Bool?

    func videoQualityTitle(_ quality: Int) -> String {
        let title = PlaybackQuality.videoTitle(quality)
        guard playbackPayload?.hasVideoStream(quality: quality) != true,
              let format = playbackPayload?.supportFormats?.first(where: { $0.quality == quality }) else { return title }
        if format.needsVIP == true { return title + "（需大会员）" }
        if format.needsLogin == true { return title + "（需登录）" }
        return title
    }

    /// 已有轨道直接切换；服务端声明但未下发的画质按所选 qn 正常补取，不能把降级响应当成成功。
    func selectQuality(video: Int? = nil, audio: Int? = nil) async -> String? {
        guard !isStopped, !isLoading, !isFetchingSource, !isSwitchingQuality,
              let originalPayload = playbackPayload else { return nil }
        if let video, !availableVideoQualities.contains(video) { return "当前视频不支持该分辨率" }
        if let audio, !availableAudioQualities.contains(audio) { return "当前视频不支持该音质" }
        guard video.map({ $0 != selectedVideoQuality }) == true || audio.map({ $0 != selectedAudioQuality }) == true else { return nil }
        let requestID = UUID()
        let initialEngineID = engineID
        qualityRequestID = requestID
        isSwitchingQuality = true
        var didBeginOpening = false
        defer {
            if qualityRequestID == requestID {
                qualityFetchTask = nil
                isFetchingQuality = false
                if !didBeginOpening { isSwitchingQuality = false }
            }
        }
        var next = configuration
        if let video { next.quality = video }
        if let audio { next.audioQuality = audio }
        do {
            var payload = originalPayload
            if let video, !payload.hasVideoStream(quality: video) {
                isFetchingQuality = true
                let loader = qualityPlaybackURLLoader
                let bvid = self.bvid, cid = self.cid
                let task = Task { try await loader(bvid, cid, video) }
                qualityFetchTask = task
                payload = try await task.value
                try Task.checkCancellation()
                guard !isStopped, qualityRequestID == requestID, engineID == initialEngineID else { return nil }
                isFetchingQuality = false
                if !payload.hasVideoStream(quality: video) {
                    return unavailableQualityMessage(video, response: payload, previous: originalPayload)
                }
            }
            let source = try PlaybackSourceBuilder.makeSource(from: payload, configuration: next)
            if let video, actualVideoQuality(in: payload, source: source, configuration: next) != video {
                return unavailableQualityMessage(video, response: payload, previous: originalPayload)
            }
            guard !isStopped, qualityRequestID == requestID, engineID == initialEngineID else { return nil }
            let position = currentTime
            let playing = isPlaying
            savePlaybackProgress()
            resumeState.prepareForOpen(at: position)
            configuration = next
            playbackPayload = payload.preservingDeclaredQualities(from: originalPayload)
            selectedVideoQuality = actualVideoQuality(in: payload, source: source, configuration: next)
            updateSelectedVideoSize(in: payload, source: source, configuration: next)
            selectedAudioQuality = source.audio == nil ? nil : payload.dash.flatMap {
                PlaybackSourceBuilder.bestAudioStream($0.allAudio, preferredQuality: next.audioQuality)?.id
            }
            sourceCandidates = source.candidates
            candidateIndex = 0
            recoveryTask?.cancel()
            recoveryTask = nil
            qualityPlaybackIntent = playing
            isLoading = true
            didBeginOpening = true
            // 换独立内核，使旧轨道的 position/firstFrame/error 无法落到新画质。
            replaceSession()
            seedDisplayAspectRatio(from: payload)
            let openedSession = session
            let openedEngineID = engineID
            do {
                try await sourceOpener(openedSession, sourceCandidates[0], position)
                try Task.checkCancellation()
                guard !isStopped, qualityRequestID == requestID, engineID == openedEngineID else { return nil }
                let shouldPlay = qualityPlaybackIntent ?? isPlaying
                if shouldPlay { openedSession.play() } else { openedSession.pause() }
                isPlaying = shouldPlay
            } catch {
                guard !isStopped, qualityRequestID == requestID, engineID == openedEngineID else { return nil }
                if !error.isCancellation { recoverFromSourceFailure(error.localizedDescription) }
                else { showPlaybackError("画质切换已取消，请重试") }
            }
            return nil
        } catch {
            guard !isStopped, qualityRequestID == requestID, engineID == initialEngineID else { return nil }
            return error.isCancellation ? nil : error.localizedDescription
        }
    }

    private func actualVideoQuality(in payload: PlayURLData, source: PlaybackSource,
                                    configuration: VideoPlaybackConfiguration) -> Int? {
        source.audio == nil ? payload.quality : payload.dash.flatMap {
            PlaybackSourceBuilder.bestVideoStream($0.video, preferredQuality: configuration.quality)?.id
        }
    }

    private func updateSelectedVideoSize(in payload: PlayURLData, source: PlaybackSource,
                                         configuration: VideoPlaybackConfiguration) {
        let stream = source.audio == nil ? nil : payload.dash.flatMap {
            PlaybackSourceBuilder.bestVideoStream($0.video, preferredQuality: configuration.quality)
        }
        selectedVideoWidth = stream?.width
        selectedVideoHeight = stream?.height
    }

    private func unavailableQualityMessage(_ quality: Int, response: PlayURLData, previous: PlayURLData) -> String {
        let format = response.supportFormats?.first { $0.quality == quality }
            ?? previous.supportFormats?.first { $0.quality == quality }
        let title = PlaybackQuality.videoTitle(quality)
        if format?.needsVIP == true { return "未取得\(title)播放地址，该档位需要大会员权限；已保留当前画质" }
        if format?.needsLogin == true { return "未取得\(title)播放地址，请确认登录状态；已保留当前画质" }
        return "服务器未提供\(title)播放地址，已保留当前画质"
    }

    private var isStopped = false
    private var isFetchingSource = false
    private var engineID = UUID()
    private var sourceCandidates: [PlaybackSource] = []
    private var candidateIndex = 0
    private var recoveryTask: Task<Void, Never>?
    private var metadata: SystemMediaMetadata?
    private(set) var isBuffering = false
    private let playbackURLLoader: PlaybackURLLoader
    private let qualityPlaybackURLLoader: QualityPlaybackURLLoader
    private let sourceOpener: PlaybackSourceOpener
    private let watchProgressReporter: @Sendable (String, Int, Double) async -> Void
    private let progressStore: PlaybackProgressStore
    var isPlaybackCompleted: Bool { resumeState.isCompleted }

    private var resumeState: PlaybackResumeState
    private var hasPreparedInitialSource = false
    private var lastSavedPosition: TimeInterval
    private let systemMediaSessionID = UUID()
    /// 上次心跳已上报到的秒数。播放中每前进 5 秒报一次；暂停、换页、
    /// 看完时再补一次，保证历史记录里的进度停在最后看的位置。
    private var lastReportedWatchTime: Double = 0

    // MARK: - 定时休眠

    /// 定时休眠的可选项。`afterVideoEnd` 表示当前这条视频播完就停。
    enum SleepOption: Equatable, Hashable {
        case minutes(Int)
        case afterVideoEnd
    }

    static let sleepOptions: [SleepOption] = [
        .minutes(15), .minutes(30), .minutes(60), .minutes(90), .minutes(120)
    ]

    /// 倒计时的到期时刻。nil 表示没有正在运行的倒计时休眠。
    private(set) var sleepDeadline: Date?
    /// 「播完就睡」是否生效。
    private(set) var sleepsAfterVideoEnd = false
    /// 菜单上当前选中的选项，给高亮对勾用。
    private(set) var selectedSleepOption: SleepOption?
    private var sleepTask: Task<Void, Never>?

    var isSleepTimerActive: Bool {
        sleepDeadline != nil || sleepsAfterVideoEnd
    }

    func setSleepTimer(_ option: SleepOption) {
        cancelSleepTimer()
        selectedSleepOption = option
        switch option {
        case .minutes(let minutes):
            sleepDeadline = Date.now.addingTimeInterval(TimeInterval(minutes) * 60)
            sleepTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(TimeInterval(minutes) * 60))
                guard !Task.isCancelled else { return }
                self?.enterSleep()
            }
        case .afterVideoEnd:
            sleepsAfterVideoEnd = true
        }
    }

    func cancelSleepTimer() {
        sleepTask?.cancel()
        sleepTask = nil
        sleepDeadline = nil
        sleepsAfterVideoEnd = false
        selectedSleepOption = nil
    }

    /// 休眠时刻到了：清掉定时状态并暂停播放。
    private func enterSleep() {
        cancelSleepTimer()
        if isPlaying {
            pause()
        }
    }

    init(
        bvid: String,
        cid: Int,
        configuration: VideoPlaybackConfiguration = .fastStart,
        playbackURLLoader: @escaping PlaybackURLLoader = { bvid, cid in
            try await VideoPreparationCache.shared.playbackURL(bvid: bvid, cid: cid)
        },
        qualityPlaybackURLLoader: @escaping QualityPlaybackURLLoader = { bvid, cid, quality in
            try await BiliAPI.playURL(bvid: bvid, cid: cid, quality: quality)
        },
        watchProgressReporter: @escaping @Sendable (String, Int, Double) async -> Void = { bvid, cid, time in
            try? await BiliAPI.reportWatchProgress(bvid: bvid, cid: cid, playedTime: time)
        },
        progressStore: PlaybackProgressStore = .shared,
        sourceOpener: @escaping PlaybackSourceOpener = { session, source, position in
            try await session.open(source: source, startTime: position)
        }
    ) {
        self.bvid = bvid
        self.cid = cid
        self.configuration = configuration
        self.playbackURLLoader = playbackURLLoader
        self.qualityPlaybackURLLoader = qualityPlaybackURLLoader
        self.sourceOpener = sourceOpener
        self.watchProgressReporter = watchProgressReporter
        self.progressStore = progressStore
        let savedPosition = progressStore.resumePosition(bvid: bvid, cid: cid)
        self.currentTime = savedPosition
        self.resumeState = PlaybackResumeState(position: savedPosition)
        self.lastSavedPosition = savedPosition
        let session = MPVPlayerSession(configuration: configuration)
        self.session = session

        bindEvents()
    }

    deinit {
        MainActor.assumeIsolated {
            savePlaybackProgress()
            SystemNowPlayingCenter.shared.deactivate(sessionID: systemMediaSessionID)
            session.stop()
        }
    }

    func updateSystemMediaMetadata(title: String, artist: String, artworkURL: URL?) {
        metadata = SystemMediaMetadata(identifier: bvid, title: title, artist: artist, artworkURL: artworkURL)
        SystemNowPlayingCenter.shared.activate(
            sessionID: systemMediaSessionID,
            metadata: SystemMediaMetadata(
                identifier: bvid,
                title: title,
                artist: artist,
                artworkURL: artworkURL
            ),
            onPlay: { [weak self] in self?.play() },
            onPause: { [weak self] in self?.pause() },
            onToggle: { [weak self] in self?.togglePlayPause() },
            onSeek: { [weak self] position in
                Task { await self?.seek(to: position) }
            }
        )
    }

    func load() async {
        guard !isStopped, !isFetchingSource else { return }
        isFetchingSource = true
        defer { isFetchingSource = false }
        isLoading = true
        errorMessage = nil
        hasRenderedFirstFrame = false
        decodedVideoWidth = nil
        decodedVideoHeight = nil
        isBuffering = false

        do {
            let payload = try await playbackURLLoader(bvid, cid)
            try Task.checkCancellation()
            guard !isStopped else { return }
            playbackPayload = payload
            seedDisplayAspectRatio(from: payload)
            let source = try PlaybackSourceBuilder.makeSource(from: payload, configuration: configuration)
            sourceCandidates = source.candidates
            candidateIndex = 0
            selectedVideoQuality = actualVideoQuality(in: payload, source: source, configuration: configuration)
            updateSelectedVideoSize(in: payload, source: source, configuration: configuration)
            selectedAudioQuality = source.audio == nil ? nil : payload.dash.flatMap {
                PlaybackSourceBuilder.bestAudioStream($0.allAudio, preferredQuality: configuration.audioQuality)?.id
            }
            duration = source.duration
            if !hasPreparedInitialSource {
                if !resumeState.hasUpdatedPosition {
                    currentTime = progressStore.resumePosition(bvid: bvid, cid: cid, duration: duration)
                }
                hasPreparedInitialSource = true
            }
            resumeState.prepareForOpen(at: currentTime)
            try await sourceOpener(session, sourceCandidates[0], currentTime)
        } catch {
            guard !isStopped else { return }
            isLoading = false
            if !error.isCancellation { showPlaybackError(error.localizedDescription) }
        }
    }

    /// 用户重试时刷新签名地址，并从最后的播放位置重新打开内核。
    func retry() async {
        guard !isStopped, !isFetchingSource, !isLoading else { return }
        savePlaybackProgress()
        isLoading = true
        recoveryTask?.cancel()
        recoveryTask = nil
        replaceSession()
        await VideoPreparationCache.shared.invalidatePlaybackURL(bvid: bvid, cid: cid)
        guard !isStopped, !Task.isCancelled else { isLoading = false; return }
        if let metadata {
            updateSystemMediaMetadata(title: metadata.title, artist: metadata.artist, artworkURL: metadata.artworkURL)
        }
        await load()
    }

    private func bindEvents() {
        let id = engineID
        session.onEvent = { [weak self] event in
            guard let self, self.engineID == id else { return }
            self.handle(event)
        }
    }

    private func replaceSession() {
        let surfacePresentation = session.surfacePresentation
        resumeState.prepareForOpen(at: currentTime)
        engineID = UUID()
        session.onEvent = nil
        session.stop()
        session = MPVPlayerSession(configuration: configuration)
        session.surfacePresentation = surfacePresentation
        bindEvents()
        hasRenderedFirstFrame = false
        decodedVideoWidth = nil
        decodedVideoHeight = nil
        isPlaying = false
        isBuffering = false
        bufferedTime = currentTime
    }

    private func showPlaybackError(_ message: String) {
        isSwitchingQuality = false
        qualityPlaybackIntent = nil
        errorMessage = message
        isPlaying = false
        isLoading = false
        isBuffering = false
        SystemNowPlayingCenter.shared.deactivate(sessionID: systemMediaSessionID)
    }

    private func recoverFromSourceFailure(_ message: String) {
        if isFetchingQuality {
            qualityRequestID = UUID()
            qualityFetchTask?.cancel()
            qualityFetchTask = nil
            isFetchingQuality = false
            isSwitchingQuality = false
        }
        savePlaybackProgress()
        guard candidateIndex + 1 < sourceCandidates.count else {
            showPlaybackError(message)
            return
        }
        candidateIndex += 1
        let source = sourceCandidates[candidateIndex]
        isLoading = true
        errorMessage = nil
        replaceSession()
        let recoverySession = session
        let recoveryEngineID = engineID
        recoveryTask = Task { [weak self] in
            guard let self, !isStopped, !Task.isCancelled, engineID == recoveryEngineID else { return }
            do {
                try await sourceOpener(recoverySession, source, currentTime)
                guard !isStopped, !Task.isCancelled, engineID == recoveryEngineID else { return }
                if let playing = qualityPlaybackIntent {
                    if playing { recoverySession.play() } else { recoverySession.pause() }
                    isPlaying = playing
                }
            } catch {
                guard !isStopped, !Task.isCancelled, engineID == recoveryEngineID else { return }
                if !error.isCancellation { showPlaybackError(error.localizedDescription) }
            }
        }
    }

    /// 真正离开视频页时立即释放播放器、观察器和网络缓冲，保证声音立刻停止。
    func stop() {
        guard !isStopped else { return }
        savePlaybackProgress()
        isStopped = true
        qualityRequestID = UUID()
        qualityFetchTask?.cancel()
        qualityFetchTask = nil
        qualityPlaybackIntent = nil
        isFetchingQuality = false
        isSwitchingQuality = false
        recoveryTask?.cancel()
        recoveryTask = nil
        cancelSleepTimer()
        Task {
            await VideoPreparationCache.shared.cancelPlaybackURL(bvid: bvid, cid: cid)
        }
        reportWatchProgress(resumeState.isCompleted ? -1 : currentTime)
        session.stop()
        SystemNowPlayingCenter.shared.deactivate(sessionID: systemMediaSessionID)
        isPlaying = false
        isLoading = false
    }

    /// 弹幕开关打开时创建控制器并开始拉取弹幕；已创建就跳过。
    func ensureDanmaku() {
        guard danmaku == nil, !isStopped else { return }
        let controller = DanmakuController(bvid: bvid, cid: cid)
        danmaku = controller
        controller.load()
        controller.setPaused(!isPlaying)
        controller.update(currentTime: currentTime)
    }

    /// 弹幕关闭时释放加载任务与画面。
    func disableDanmaku() {
        danmaku?.shutdown()
        danmaku = nil
    }

    /// 被另一个视频页盖住时调用。只停声音和画面，不释放播放项目。
    func pause() {
        savePlaybackProgress()
        danmaku?.setPaused(true)
        guard !isStopped else { return }
        if qualityPlaybackIntent != nil || !hasRenderedFirstFrame { qualityPlaybackIntent = false }
        session.pause()
        isPlaying = false
        reportWatchProgress(resumeState.isCompleted ? -1 : currentTime)
        SystemNowPlayingCenter.shared.updatePlaybackState(
            isPlaying: false,
            sessionID: systemMediaSessionID
        )
    }

    func play() {
        guard !isStopped, errorMessage == nil else { return }
        if qualityPlaybackIntent != nil, !hasRenderedFirstFrame {
            qualityPlaybackIntent = true
            return
        }
        guard hasRenderedFirstFrame else { return }
        danmaku?.setPaused(false)
        if resumeState.isCompleted {
            // EOF 会卸载文件，必须重新打开当前地址，单纯 seek/play 不会重播。
            resumeState.seek(to: 0)
            currentTime = 0
            danmaku?.seek(to: 0)
            savePlaybackProgress()
            isLoading = true
            hasRenderedFirstFrame = false
            bufferedTime = 0
            recoveryTask?.cancel()
            recoveryTask = Task { [weak self] in
                guard let self else { return }
                do {
                    if sourceCandidates.indices.contains(candidateIndex) {
                        try await sourceOpener(session, sourceCandidates[candidateIndex], 0)
                    } else {
                        await load()
                    }
                    guard !isStopped, !Task.isCancelled else { return }
                    session.play()
                } catch {
                    if !isStopped, !error.isCancellation { showPlaybackError(error.localizedDescription) }
                }
            }
        } else {
            session.play()
        }
        isPlaying = true
        SystemNowPlayingCenter.shared.updatePlaybackState(
            isPlaying: true,
            sessionID: systemMediaSessionID
        )
    }

    func togglePlayPause() {
        guard !isStopped, errorMessage == nil, hasRenderedFirstFrame else { return }
        if isPlaying { pause() } else { play() }
    }

    /// 手指抬起后只调用一次，播放器负责精确到关键帧附近的跳转。
    func seek(to seconds: Double) async {
        guard !isStopped, seconds.isFinite else { return }
        let needsReopen = resumeState.isCompleted
        let wasPlaying = isPlaying
        let upperBound = duration > 0 ? duration : max(seconds, 0)
        let target = min(max(seconds, 0), upperBound)
        currentTime = target
        resumeState.seek(to: target)
        danmaku?.seek(to: target)
        savePlaybackProgress()
        reportWatchProgress(target)
        SystemNowPlayingCenter.shared.updateElapsed(
            target,
            sessionID: systemMediaSessionID,
            force: true
        )
        if needsReopen {
            // 播完后拖动也要重新加载文件；清除 completed 后再点播放已经无法
            // 判断文件曾被 EOF 卸载，因此在这次 seek 内完成重开并保持暂停。
            isLoading = true
            hasRenderedFirstFrame = false
            bufferedTime = target
            do {
                if sourceCandidates.indices.contains(candidateIndex) {
                    try await sourceOpener(session, sourceCandidates[candidateIndex], target)
                } else {
                    await load()
                }
                guard !isStopped, !Task.isCancelled else { return }
                if wasPlaying { session.play() } else { session.pause() }
            } catch {
                if !isStopped, !error.isCancellation { showPlaybackError(error.localizedDescription) }
            }
        } else {
            await session.seek(to: target)
        }
    }

    /// 暂停、退出、切后台时同步落盘；尚未真正播放过的加载页不能覆盖旧记录。
    func savePlaybackProgress() {
        guard !isStopped else { return }
        if resumeState.isCompleted {
            progressStore.remove(bvid: bvid, cid: cid)
        } else if resumeState.hasUpdatedPosition {
            progressStore.save(bvid: bvid, cid: cid, position: resumeState.position, duration: duration)
            lastSavedPosition = resumeState.position
        }
    }

    private func seedDisplayAspectRatio(from payload: PlayURLData) {
        guard !hasDecodedAspectRatio, let dash = payload.dash,
              let stream = PlaybackSourceBuilder.bestVideoStream(dash.video, preferredQuality: configuration.quality),
              let width = stream.width, let height = stream.height, width > 0, height > 0 else { return }
        displayAspectRatio = Double(width) / Double(height)
    }

    private func handle(_ event: PlayerPlaybackEvent) {
        guard !isStopped, errorMessage == nil else { return }

        switch event {
        case .firstFrame:
            isSwitchingQuality = false
            hasRenderedFirstFrame = true
            isLoading = false
            isBuffering = false
            if let playing = qualityPlaybackIntent {
                if playing { session.play() } else { session.pause() }
                isPlaying = playing
                qualityPlaybackIntent = nil
            }
            // mpv 的音频输出已经建好，这里是重试音频会话激活的安全窗口：
            // 启动时那次可能失败，失败的会话不会出现在系统的「正在播放」里。
            if isPlaying { PlaybackAudioSession.activateOnce() }
        case .playing(let playing):
            danmaku?.setPaused(!playing)
            if qualityPlaybackIntent == false, playing {
                session.pause()
                isPlaying = false
                return
            }
            isPlaying = playing
            if !playing { savePlaybackProgress() }
            SystemNowPlayingCenter.shared.updatePlaybackState(
                isPlaying: playing,
                sessionID: systemMediaSessionID
            )
        case .buffering(let buffering):
            isBuffering = buffering
            if !hasRenderedFirstFrame { isLoading = true }
        case .position(let position):
            guard hasRenderedFirstFrame, !isLoading, (!isSwitchingQuality || isFetchingQuality),
                  resumeState.accept(position: position) else { return }
            // MPVEngine limits progress delivery before dispatching to the main queue.
            currentTime = position
            danmaku?.update(currentTime: position)
            if abs(position - lastSavedPosition) >= 5 { savePlaybackProgress() }
            // 观看进度心跳：距离上次上报前进超过 5 秒才发，对齐官方
            // 网页播放器的节奏。
            if isPlaying, position - lastReportedWatchTime >= 5 {
                reportWatchProgress(position)
            }
            SystemNowPlayingCenter.shared.updateElapsed(
                position,
                sessionID: systemMediaSessionID
            )
        case .seekCompleted(let position):
            guard hasRenderedFirstFrame, !isLoading, (!isSwitchingQuality || isFetchingQuality),
                  resumeState.confirm(position: position) else { return }
            currentTime = position
            savePlaybackProgress()
            SystemNowPlayingCenter.shared.updateElapsed(position, sessionID: systemMediaSessionID, force: true)
        case .duration(let duration):
            if duration.isFinite, duration > 0 {
                self.duration = duration
                SystemNowPlayingCenter.shared.updateDuration(
                    duration,
                    sessionID: systemMediaSessionID
                )
            }
        case .buffered(let buffered):
            let next = max(currentTime + buffered, currentTime)
            // 缓存前沿只在明显前进时才写：这个属性没有界面消费缓冲区段时
            // 也会把控制层子树整体打失效，高频事件纯属浪费。
            if abs(next - bufferedTime) >= 0.25 { bufferedTime = next }
        case .displayAspectRatio(let ratio):
            if ratio.isFinite, ratio > 0 {
                displayAspectRatio = ratio
                hasDecodedAspectRatio = true
            }
        case .decodedVideoSize(let width, let height):
            if width > 0, height > 0 {
                decodedVideoWidth = width
                decodedVideoHeight = height
            }
        case .ended:
            guard hasRenderedFirstFrame, !isLoading, !isSwitchingQuality else { return }
            isPlaying = false
            isLoading = false
            danmaku?.setPaused(true)
            resumeState.complete()
            savePlaybackProgress()
            // 看完时 played_time 传 -1，服务端会把它记成「已看完」。
            reportWatchProgress(-1)
            if sleepsAfterVideoEnd {
                enterSleep()
            }
            SystemNowPlayingCenter.shared.updatePlaybackState(
                isPlaying: false,
                sessionID: systemMediaSessionID
            )
        case .error(let message):
            recoverFromSourceFailure(message)
        }
    }

    /// 观看进度上报（心跳）。失败静默：历史记录是尽力而为的副产品，
    /// 不能因为上报失败打断或提示播放。
    private func reportWatchProgress(_ playedTime: Double) {
        guard playedTime != lastReportedWatchTime, playedTime > 0 || currentTime > 0 else { return }
        lastReportedWatchTime = playedTime
        let bvid = self.bvid
        let cid = self.cid
        let reporter = watchProgressReporter
        Task.detached(priority: .utility) {
            await reporter(bvid, cid, playedTime)
        }
    }
}
