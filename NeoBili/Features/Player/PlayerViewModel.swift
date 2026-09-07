import Foundation
import SwiftUI

typealias PlaybackURLLoader = @Sendable (String, Int) async throws -> PlayURLData

/// 提前保存视频详情和播放地址，点进卡片时就不必重复等待相同请求。
/// 这里只缓存接口返回的小段文字数据，不会提前下载整段视频。
actor VideoPreparationCache {
    static let shared = VideoPreparationCache()

    private struct PlaybackKey: Hashable, Sendable {
        let bvid: String
        let cid: Int
    }

    private struct CachedValue<Value: Sendable>: Sendable {
        let value: Value
        let savedAt: Date
    }

    private let lifetime: TimeInterval = 5 * 60
    private let maximumEntries = 8
    /// 同时最多预取几个视频。数字越大越占用带宽，会拖慢用户真正点开的那个。
    private let maximumConcurrentPrefetches = 2
    /// 等待队列的上限。超过这个数量说明用户在快速滑动，多余的卡片直接放弃预取。
    private let maximumQueuedPrefetches = 4

    private var details: [String: CachedValue<VideoDetail>] = [:]
    private var playbackURLs: [PlaybackKey: CachedValue<PlayURLData>] = [:]
    private var detailTasks: [String: Task<VideoDetail, Error>] = [:]
    private var playbackTasks: [PlaybackKey: Task<PlayURLData, Error>] = [:]
    private var playbackRequestIDs: [PlaybackKey: UUID] = [:]
    private var activePrefetchCount = 0
    private var prefetchWaiters: [CheckedContinuation<Void, Never>] = []

    /// 用户真正点开视频时走这里，不受预取名额限制；如果同一个请求正在预取，直接复用它。
    func detail(for bvid: String) async throws -> VideoDetail {
        removeExpiredValues()
        if let cached = details[bvid] {
            return cached.value
        }
        if let existingTask = detailTasks[bvid] {
            return try await existingTask.value
        }

        let task = Task { try await BiliAPI.videoDetail(bvid: bvid) }
        detailTasks[bvid] = task
        do {
            let detail = try await task.value
            detailTasks[bvid] = nil
            details[bvid] = CachedValue(value: detail, savedAt: Date())
            trimIfNeeded()
            return detail
        } catch {
            detailTasks[bvid] = nil
            throw error
        }
    }

    func playbackURL(bvid: String, cid: Int) async throws -> PlayURLData {
        removeExpiredValues()
        let key = PlaybackKey(bvid: bvid, cid: cid)
        if let cached = playbackURLs[key] {
            return cached.value
        }
        if let existingTask = playbackTasks[key] {
            if existingTask.isCancelled {
                playbackTasks[key] = nil
                playbackRequestIDs[key] = nil
            } else {
                return try await existingTask.value
            }
        }

        let requestID = UUID()
        let task = Task { try await BiliAPI.playURL(bvid: bvid, cid: cid) }
        playbackTasks[key] = task
        playbackRequestIDs[key] = requestID
        do {
            let payload = try await task.value
            if playbackRequestIDs[key] == requestID {
                playbackTasks[key] = nil
                playbackRequestIDs[key] = nil
                playbackURLs[key] = CachedValue(value: payload, savedAt: Date())
            }
            trimIfNeeded()
            return payload
        } catch {
            if playbackRequestIDs[key] == requestID {
                playbackTasks[key] = nil
                playbackRequestIDs[key] = nil
            }
            throw error
        }
    }

    /// A page-owned playback request is no longer useful after its player is
    /// closed. Cancel the shared in-flight task as well as the caller's wait.
    func cancelPlaybackURL(bvid: String, cid: Int) {
        let key = PlaybackKey(bvid: bvid, cid: cid)
        playbackTasks[key]?.cancel()
        playbackTasks[key] = nil
        playbackRequestIDs[key] = nil
    }

    func invalidatePlaybackURL(bvid: String, cid: Int) {
        cancelPlaybackURL(bvid: bvid, cid: cid)
        playbackURLs[PlaybackKey(bvid: bvid, cid: cid)] = nil
    }

    /// 卡片出现在屏幕上时调用。推荐卡已经有 cid；搜索卡没有，所以先取一次详情。
    func prefetch(bvid: String, cid: Int? = nil) async {
        removeExpiredValues()
        if let cid, playbackURLs[PlaybackKey(bvid: bvid, cid: cid)] != nil { return }
        if cid == nil, let detail = details[bvid]?.value,
           playbackURLs[PlaybackKey(bvid: bvid, cid: detail.cid)] != nil { return }

        guard await acquirePrefetchSlot() else { return }
        defer { releasePrefetchSlot() }
        guard !Task.isCancelled else { return }

        do {
            let resolvedCid: Int
            if let cid {
                resolvedCid = cid
            } else {
                resolvedCid = try await detail(for: bvid).cid
            }
            _ = try await playbackURL(bvid: bvid, cid: resolvedCid)
        } catch {
            // 预取失败不能影响列表使用；用户真正点开时仍会正常重试并显示错误。
        }
    }

    private func acquirePrefetchSlot() async -> Bool {
        if activePrefetchCount < maximumConcurrentPrefetches {
            activePrefetchCount += 1
            return true
        }
        guard prefetchWaiters.count < maximumQueuedPrefetches else { return false }
        await withCheckedContinuation { prefetchWaiters.append($0) }
        return true
    }

    private func releasePrefetchSlot() {
        if prefetchWaiters.isEmpty {
            activePrefetchCount = max(activePrefetchCount - 1, 0)
        } else {
            prefetchWaiters.removeFirst().resume()
        }
    }

    private func removeExpiredValues() {
        let cutoff = Date().addingTimeInterval(-lifetime)
        details = details.filter { $0.value.savedAt >= cutoff }
        playbackURLs = playbackURLs.filter { $0.value.savedAt >= cutoff }
    }

    private func trimIfNeeded() {
        if details.count > maximumEntries,
           let oldest = details.min(by: { $0.value.savedAt < $1.value.savedAt })?.key {
            details[oldest] = nil
        }
        if playbackURLs.count > maximumEntries,
           let oldest = playbackURLs.min(by: { $0.value.savedAt < $1.value.savedAt })?.key {
            playbackURLs[oldest] = nil
        }
    }
}

@MainActor
@Observable
final class PlayerViewModel {
    let bvid: String
    let cid: Int
    private(set) var configuration: VideoPlaybackConfiguration
    private(set) var session: MPVPlayerSession

    private(set) var isLoading = true
    private(set) var errorMessage: String?
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    /// 已经缓冲到的位置，进度条用它画出比播放位置更靠前的浅色区段。
    private(set) var bufferedTime: Double = 0
    private(set) var hasRenderedFirstFrame = false

    private var playbackPayload: PlayURLData?
    private(set) var isSwitchingQuality = false

    var availableVideoQualities: [Int] {
        Array(Set(playbackPayload?.dash?.video.filter { URL(string: $0.baseUrl) != nil }.map(\.id) ?? [])).sorted(by: >)
    }

    var availableAudioQualities: [Int] {
        Array(Set(playbackPayload?.dash?.allAudio.filter { URL(string: $0.baseUrl) != nil }.map(\.id) ?? []))
            .sorted { PlaybackQuality.audioRank($0) > PlaybackQuality.audioRank($1) }
    }

    var selectedVideoQuality: Int? {
        guard let payload = playbackPayload else { return nil }
        return payload.dash.flatMap { PlaybackSourceBuilder.bestVideoStream($0.video, preferredQuality: configuration.quality)?.id }
            ?? payload.quality
    }

    var selectedAudioQuality: Int? {
        playbackPayload?.dash.flatMap {
            PlaybackSourceBuilder.bestAudioStream($0.allAudio, preferredQuality: configuration.audioQuality)?.id
        }
    }

    /// 使用已获取的音视频轨道重新打开当前内核，不重新补查详情或丢失播放位置。
    func selectQuality(video: Int? = nil, audio: Int? = nil) async -> String? {
        guard !isStopped, !isLoading, !isSwitchingQuality, let payload = playbackPayload else { return nil }
        if let video, !availableVideoQualities.contains(video) { return "当前视频不支持该分辨率" }
        if let audio, !availableAudioQualities.contains(audio) { return "当前视频不支持该音质" }
        var next = configuration
        if let video { next.quality = video }
        if let audio { next.audioQuality = audio }
        guard next != configuration else { return nil }
        do {
            let source = try PlaybackSourceBuilder.makeSource(from: payload, configuration: next)
            let position = currentTime
            let playing = isPlaying
            isSwitchingQuality = true
            isLoading = true
            recoveryTask?.cancel()
            sourceCandidates = source.candidates
            candidateIndex = 0
            configuration = next
            bufferedTime = position
            try await session.open(source: sourceCandidates[0], startTime: position)
            if playing { session.play() } else { session.pause() }
            return nil
        } catch {
            isSwitchingQuality = false
            isLoading = false
            return error.isCancellation ? nil : error.localizedDescription
        }
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
    private let watchProgressReporter: @Sendable (String, Int, Double) async -> Void
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

    /// 剩余时间（分钟），给界面显示用。只在倒计时休眠时有值。
    var sleepRemainingMinutes: Int? {
        guard let sleepDeadline else { return nil }
        return max(0, Int(ceil(sleepDeadline.timeIntervalSinceNow / 60)))
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
        watchProgressReporter: @escaping @Sendable (String, Int, Double) async -> Void = { bvid, cid, time in
            try? await BiliAPI.reportWatchProgress(bvid: bvid, cid: cid, playedTime: time)
        }
    ) {
        self.bvid = bvid
        self.cid = cid
        self.configuration = configuration
        self.playbackURLLoader = playbackURLLoader
        self.watchProgressReporter = watchProgressReporter
        let session = MPVPlayerSession(configuration: configuration)
        self.session = session

        bindEvents()
    }

    deinit {
        MainActor.assumeIsolated {
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
        isBuffering = false

        do {
            let payload = try await playbackURLLoader(bvid, cid)
            try Task.checkCancellation()
            guard !isStopped else { return }
            playbackPayload = payload
            let source = try PlaybackSourceBuilder.makeSource(from: payload, configuration: configuration)
            sourceCandidates = source.candidates
            candidateIndex = 0
            duration = source.duration
            try await session.open(source: sourceCandidates[0], startTime: currentTime)
        } catch {
            guard !isStopped else { return }
            isLoading = false
            if !error.isCancellation { showPlaybackError(error.localizedDescription) }
        }
    }

    /// 用户重试时刷新签名地址，并从最后的播放位置重新打开内核。
    func retry() async {
        guard !isStopped, !isFetchingSource, !isLoading else { return }
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
        engineID = UUID()
        session.onEvent = nil
        session.stop()
        session = MPVPlayerSession(configuration: configuration)
        bindEvents()
        hasRenderedFirstFrame = false
        isPlaying = false
        isBuffering = false
        bufferedTime = currentTime
    }

    private func showPlaybackError(_ message: String) {
        isSwitchingQuality = false
        errorMessage = message
        isPlaying = false
        isLoading = false
        isBuffering = false
        SystemNowPlayingCenter.shared.deactivate(sessionID: systemMediaSessionID)
    }

    private func recoverFromSourceFailure(_ message: String) {
        guard candidateIndex + 1 < sourceCandidates.count else {
            showPlaybackError(message)
            return
        }
        candidateIndex += 1
        let source = sourceCandidates[candidateIndex]
        isLoading = true
        errorMessage = nil
        replaceSession()
        recoveryTask = Task { [weak self] in
            guard let self, !isStopped, !Task.isCancelled else { return }
            do { try await session.open(source: source, startTime: currentTime) }
            catch { if !isStopped { showPlaybackError(error.localizedDescription) } }
        }
    }

    /// 真正离开视频页时立即释放播放器、观察器和网络缓冲，保证声音立刻停止。
    func stop() {
        guard !isStopped else { return }
        isStopped = true
        recoveryTask?.cancel()
        recoveryTask = nil
        cancelSleepTimer()
        Task {
            await VideoPreparationCache.shared.cancelPlaybackURL(bvid: bvid, cid: cid)
        }
        reportWatchProgress(currentTime)
        session.stop()
        SystemNowPlayingCenter.shared.deactivate(sessionID: systemMediaSessionID)
        isPlaying = false
        isLoading = false
    }

    /// 被另一个视频页盖住时调用。只停声音和画面，不释放播放项目。
    func pause() {
        guard isPlaying else { return }
        session.pause()
        isPlaying = false
        reportWatchProgress(currentTime)
        SystemNowPlayingCenter.shared.updatePlaybackState(
            isPlaying: false,
            sessionID: systemMediaSessionID
        )
    }

    func play() {
        guard !isStopped, errorMessage == nil, hasRenderedFirstFrame else { return }
        session.play()
        isPlaying = true
        SystemNowPlayingCenter.shared.updatePlaybackState(
            isPlaying: true,
            sessionID: systemMediaSessionID
        )
    }

    func togglePlayPause() {
        guard !isStopped, errorMessage == nil, hasRenderedFirstFrame else { return }
        if isPlaying {
            session.pause()
        } else {
            session.play()
        }
        isPlaying.toggle()
        SystemNowPlayingCenter.shared.updatePlaybackState(
            isPlaying: isPlaying,
            sessionID: systemMediaSessionID
        )
    }

    /// 手指抬起后只调用一次，播放器负责精确到关键帧附近的跳转。
    func seek(to seconds: Double) async {
        let upperBound = duration > 0 ? duration : max(seconds, 0)
        let target = min(max(seconds, 0), upperBound)
        currentTime = target
        SystemNowPlayingCenter.shared.updateElapsed(
            target,
            sessionID: systemMediaSessionID,
            force: true
        )
        await session.seek(to: target)
    }

    private func handle(_ event: PlayerPlaybackEvent) {
        guard !isStopped, errorMessage == nil else { return }

        switch event {
        case .firstFrame:
            isSwitchingQuality = false
            hasRenderedFirstFrame = true
            isLoading = false
            isBuffering = false
            // mpv 的音频输出已经建好，这里是重试音频会话激活的安全窗口：
            // 启动时那次可能失败，失败的会话不会出现在系统的「正在播放」里。
            PlaybackAudioSession.activateOnce()
        case .playing(let playing):
            isPlaying = playing
            SystemNowPlayingCenter.shared.updatePlaybackState(
                isPlaying: playing,
                sessionID: systemMediaSessionID
            )
        case .buffering(let buffering):
            isBuffering = buffering
            if !hasRenderedFirstFrame { isLoading = true }
        case .position(let position):
            guard hasRenderedFirstFrame, !isSwitchingQuality else { return }
            currentTime = position
            // 观看进度心跳：距离上次上报前进超过 5 秒才发，对齐官方
            // 网页播放器的节奏。
            if isPlaying, position - lastReportedWatchTime >= 5 {
                reportWatchProgress(position)
            }
            SystemNowPlayingCenter.shared.updateElapsed(
                position,
                sessionID: systemMediaSessionID
            )
        case .duration(let duration):
            if duration > 0 {
                self.duration = duration
                SystemNowPlayingCenter.shared.updateDuration(
                    duration,
                    sessionID: systemMediaSessionID
                )
            }
        case .buffered(let buffered):
            bufferedTime = max(currentTime + buffered, currentTime)
        case .ended:
            isPlaying = false
            isLoading = false
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
        if playedTime > 0 {
            lastReportedWatchTime = playedTime
        }
        let bvid = self.bvid
        let cid = self.cid
        let reporter = watchProgressReporter
        Task.detached(priority: .utility) {
            await reporter(bvid, cid, playedTime)
        }
    }
}
