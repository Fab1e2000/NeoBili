#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation
import SwiftUI

typealias PlaybackURLLoader = @Sendable (String, Int) async throws -> PlayURLData
typealias QualityPlaybackURLLoader = @Sendable (String, Int, Int) async throws -> PlayURLData
typealias PlaybackSourceOpener = @MainActor (MPVPlayerSession, PlaybackSource, TimeInterval) async throws -> Void

@MainActor
@Observable
final class PlayerViewModel {
    @ObservationIgnored private let dependencies: PlaybackDependencies
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
    private(set) var playbackRate: Double = 1

    private var rateBeforeLongPress: Double?

    func beginTemporaryDoubleSpeed() {
        guard isPlaying, hasRenderedFirstFrame, !isLoading, errorMessage == nil,
              !isStopped, rateBeforeLongPress == nil else { return }
        rateBeforeLongPress = playbackRate
        selectPlaybackRate(2)
    }

    func endTemporaryDoubleSpeed() {
        guard let rate = rateBeforeLongPress else { return }
        rateBeforeLongPress = nil
        selectPlaybackRate(rate)
    }

    func selectPlaybackRate(_ rate: Double) {
        guard !isStopped, PlaybackSpeed.options.contains(rate), playbackRate != rate else { return }
        reporting.setPlaybackRate(rate)
        playbackRate = rate
        session.setPlaybackRate(rate)
        dependencies.systemMedia.updateElapsed(currentTime, sessionID: systemMediaSessionID, force: true)
        dependencies.systemMedia.updatePlaybackState(isPlaying: isPlaying,
            sessionID: systemMediaSessionID, rate: rate)
    }

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
        if format.needsVIP == true { return title + String(localized: "（需大会员）") }
        if format.needsLogin == true { return title + String(localized: "（需登录）") }
        return title
    }

    /// 已有轨道直接切换；服务端声明但未下发的画质按所选 qn 正常补取，不能把降级响应当成成功。
    func selectQuality(video: Int? = nil, audio: Int? = nil) async -> String? {
        guard !isStopped, !isLoading, !isFetchingSource, !isSwitchingQuality,
              let originalPayload = playbackPayload else { return nil }
        if let video, !availableVideoQualities.contains(video) { return String(localized: "当前视频不支持该分辨率") }
        if let audio, !availableAudioQualities.contains(audio) { return String(localized: "当前视频不支持该音质") }
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
                else { showPlaybackError(String(localized: "画质切换已取消，请重试")) }
            }
            return nil
        } catch {
            guard !isStopped, qualityRequestID == requestID, engineID == initialEngineID else { return nil }
            return error.isCancellation ? nil : error.localizedDescription
        }
    }

    private func actualVideoQuality(in payload: PlayURLData, source: PlaybackSource,
                                    configuration: VideoPlaybackConfiguration) -> Int? {
        !source.isDASH ? payload.quality : payload.dash.flatMap {
            PlaybackSourceBuilder.bestVideoStream($0.video, preferredQuality: configuration.quality)?.id
        }
    }

    private func updateSelectedVideoSize(in payload: PlayURLData, source: PlaybackSource,
                                         configuration: VideoPlaybackConfiguration) {
        let stream = !source.isDASH ? nil : payload.dash.flatMap {
            PlaybackSourceBuilder.bestVideoStream($0.video, preferredQuality: configuration.quality)
        }
        selectedVideoWidth = stream?.width
        selectedVideoHeight = stream?.height
    }

    private func unavailableQualityMessage(_ quality: Int, response: PlayURLData, previous: PlayURLData) -> String {
        let format = response.supportFormats?.first { $0.quality == quality }
            ?? previous.supportFormats?.first { $0.quality == quality }
        let title = PlaybackQuality.videoTitle(quality)
        if format?.needsVIP == true { return String(localized: "未取得\(title)播放地址，该档位需要大会员权限；已保留当前画质") }
        if format?.needsLogin == true { return String(localized: "未取得\(title)播放地址，请确认登录状态；已保留当前画质") }
        return String(localized: "服务器未提供\(title)播放地址，已保留当前画质")
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
    @ObservationIgnored private let playbackRequestOwnerID: UUID
    @ObservationIgnored private let loginSessionID: UUID
    private let qualityPlaybackURLLoader: QualityPlaybackURLLoader
    private let sourceOpener: PlaybackSourceOpener
    @ObservationIgnored private let reporting: PlaybackReportingCoordinator
    private let progressStore: PlaybackProgressStore
    var isPlaybackCompleted: Bool { resumeState.isCompleted }

    private var resumeState: PlaybackResumeState
    private var hasPreparedInitialSource = false
    private var lastSavedPosition: TimeInterval
    private let systemMediaSessionID = UUID()

    // MARK: - 定时休眠

    typealias SleepOption = PlaybackSleepTimer.Option
    static let sleepOptions = PlaybackSleepTimer.options
    private let sleepTimer: PlaybackSleepTimer
    @ObservationIgnored private let danmakuLoader: @Sendable (Int) async throws -> [DanmakuItem]

    var sleepDeadline: Date? { sleepTimer.deadline }
    var sleepsAfterVideoEnd: Bool { sleepTimer.afterVideoEnd }
    var selectedSleepOption: SleepOption? { sleepTimer.selectedOption }
    var isSleepTimerActive: Bool { sleepTimer.isActive }

    func setSleepTimer(_ option: SleepOption) {
        sleepTimer.set(option) { [weak self] in self?.enterSleep() }
    }

    func cancelSleepTimer() { sleepTimer.cancel() }

    private func enterSleep() {
        cancelSleepTimer()
        // 取流或重建内核期间也要留下暂停意图，阻止迟到的自动播放。
        pause()
    }

    init(telemetry: TelemetryService? = nil,
        bvid: String,
        cid: Int,
        aid: Int = 0, playbackEntry: PlaybackEntry = .other, playbackSession: String? = nil,
        configuration: VideoPlaybackConfiguration = .fastStart,
        playbackURLLoader: PlaybackURLLoader? = nil,
        qualityPlaybackURLLoader: QualityPlaybackURLLoader? = nil,
        watchProgressReporter: (@Sendable (String, Int, Double) async -> Void)? = nil,
        watchReportReporter: (@Sendable (PlaybackWatchReport) async -> Void)? = nil,
        progressStore: PlaybackProgressStore? = nil,
        watchProgressClock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        sleepWaiter: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        },
        danmakuLoader: @escaping @Sendable (Int) async throws -> [DanmakuItem] = ApplicationServices.loadDanmaku,
        sourceOpener: @escaping PlaybackSourceOpener = { session, source, position in
            try await session.open(source: source, startTime: position)
        },
        dependencies: PlaybackDependencies = .live
    ) {
        self.dependencies = dependencies
        let telemetry = telemetry ?? dependencies.services.telemetry
        let progressStore = progressStore ?? dependencies.progress
        let services = dependencies.services
        let watchPlaybackSession = playbackSession ?? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        self.bvid = bvid
        self.cid = cid
        self.configuration = configuration
        let playbackRequestOwnerID = UUID()
        let loginSessionID = services.session.currentID()
        self.playbackRequestOwnerID = playbackRequestOwnerID
        self.loginSessionID = loginSessionID
        self.playbackURLLoader = playbackURLLoader ?? { bvid, cid in
            try await dependencies.preparation.playbackURL(bvid: bvid, cid: cid,
                ownerID: playbackRequestOwnerID, expectedSessionID: loginSessionID)
        }
        self.qualityPlaybackURLLoader = qualityPlaybackURLLoader ?? { bvid, cid, quality in
            try await services.video.playURL(bvid: bvid, cid: cid, quality: quality)
        }
        self.sourceOpener = sourceOpener
        self.sleepTimer = PlaybackSleepTimer(waiter: sleepWaiter)
        self.danmakuLoader = danmakuLoader
        let watchProgressSender: PlaybackWatchProgressSender?
        let watchReportSender: PlaybackWatchReportSender?
        // Bind before scheduling any async work: a delayed heartbeat must never
        // acquire credentials from a later login, including the same account.
        if let watchReportReporter {
            watchProgressSender = nil
            watchReportSender = PlaybackWatchReportSender(report: watchReportReporter)
        } else if let watchProgressReporter {
            watchReportSender = nil
            watchProgressSender = PlaybackWatchProgressSender { time in
                await watchProgressReporter(bvid, cid, time)
            }
        } else {
            watchProgressSender = nil
            watchReportSender = dependencies.watchReports.sender(loginSessionID: loginSessionID, bvid: bvid, cid: cid, serverReport: { report in
                if report.aid > 0 {
                    return try? await services.library.reportAppWatch(bvid: bvid, aid: report.aid, cid: cid, report: report,
                                                     expectedSessionID: loginSessionID)
                } else {
                    guard report.delivery != .start else { return nil }
                    try? await services.library.reportWatchProgress(bvid: bvid, cid: cid, playedTime: report.position,
                                                          expectedSessionID: loginSessionID)
                    return nil
                }
            })
        }
        self.reporting = PlaybackReportingCoordinator(telemetry: telemetry, cid: cid, loginSessionID: loginSessionID,
            playbackEntry: playbackEntry, playbackSession: watchPlaybackSession, aid: aid,
            clock: watchProgressClock, progressSender: watchProgressSender, reportSender: watchReportSender)
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
            reporting.enqueueLegacyCheckpoint()
            reporting.finishWatchReport(context: reportingContext)
            dependencies.systemMedia.deactivate(sessionID: systemMediaSessionID)
            danmaku?.shutdown()
            sleepTimer.cancel()
            session.stop()
        }
    }

    func updateSystemMediaMetadata(title: String, artist: String, artworkURL: URL?) {
        metadata = SystemMediaMetadata(identifier: bvid, title: title, artist: artist, artworkURL: artworkURL)
        dependencies.systemMedia.activate(
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
        reporting.checkpointWatchProgress(context: reportingContext)
        reporting.interrupt(discontinuity: true)
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
        await dependencies.preparation.invalidatePlaybackURL(bvid: bvid, cid: cid,
                                                                 expectedSessionID: loginSessionID)
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
        reporting.checkpointWatchProgress(context: reportingContext)
        reporting.interrupt(discontinuity: true)
        let surfacePresentation = session.surfacePresentation
        resumeState.prepareForOpen(at: currentTime)
        engineID = UUID()
        session.onEvent = nil
        session.stop()
        session = MPVPlayerSession(configuration: configuration)
        session.setPlaybackRate(playbackRate)
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
        reporting.checkpointWatchProgress(context: reportingContext)
        reporting.interrupt(discontinuity: true)
        isSwitchingQuality = false
        qualityPlaybackIntent = nil
        errorMessage = message
        isPlaying = false
        isLoading = false
        isBuffering = false
        dependencies.systemMedia.deactivate(sessionID: systemMediaSessionID)
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
        endTemporaryDoubleSpeed()
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
        disableDanmaku()
        Task {
            await dependencies.preparation.cancelPlaybackURL(bvid: bvid, cid: cid,
                ownerID: playbackRequestOwnerID, sessionID: loginSessionID)
        }
        reporting.enqueueLegacyCheckpoint()
        reporting.finishPlayerBehavior(context: reportingContext)
        reporting.finishWatchReport(context: reportingContext)
        reporting.interrupt()
        session.stop()
        dependencies.systemMedia.deactivate(sessionID: systemMediaSessionID)
        isPlaying = false
        isLoading = false
    }

    /// 弹幕开关打开时创建控制器并开始拉取弹幕；已创建就跳过。
    func ensureDanmaku() {
        guard danmaku == nil, !isStopped else { return }
        let controller = DanmakuController(bvid: bvid, cid: cid, loader: danmakuLoader)
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
        endTemporaryDoubleSpeed()
        savePlaybackProgress()
        danmaku?.setPaused(true)
        guard !isStopped else { return }
        if qualityPlaybackIntent != nil || !hasRenderedFirstFrame { qualityPlaybackIntent = false }
        session.pause()
        reporting.setPaused(true)
        isPlaying = false
        reporting.checkpointWatchProgress(context: reportingContext)
        reporting.interrupt()
        dependencies.systemMedia.updatePlaybackState(
            isPlaying: false,
            sessionID: systemMediaSessionID, rate: playbackRate
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
            reporting.resetWatchReport(context: reportingContext)
            reporting.interrupt(discontinuity: true)
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
        dependencies.systemMedia.updatePlaybackState(
            isPlaying: true,
            sessionID: systemMediaSessionID, rate: playbackRate
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
        if needsReopen { reporting.resetWatchReport(context: reportingContext) }
        let wasPlaying = isPlaying
        let upperBound = duration > 0 ? duration : max(seconds, 0)
        let target = min(max(seconds, 0), upperBound)
        reporting.checkpointWatchProgress(context: reportingContext)
        reporting.interrupt(discontinuity: true)
        currentTime = target
        resumeState.seek(to: target)
        danmaku?.seek(to: target)
        savePlaybackProgress()
        dependencies.systemMedia.updateElapsed(
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
            if isPlaying { session.refreshAudioFocusIfNeeded() }
            reporting.startPlayerBehaviorIfReady(context: reportingContext)
        case .playing(let playing):
            reporting.recordPlayingTransition(playing, context: reportingContext)
            reporting.setPaused(!playing)
            danmaku?.setPaused(!playing)
            if qualityPlaybackIntent == false, playing {
                session.pause()
                isPlaying = false
                return
            }
            isPlaying = playing
            reporting.startPlayerBehaviorIfReady(context: reportingContext)
            if !playing {
                endTemporaryDoubleSpeed()
                savePlaybackProgress()
                reporting.checkpointWatchProgress(context: reportingContext)
                reporting.interrupt()
            }
            dependencies.systemMedia.updatePlaybackState(
                isPlaying: playing,
                sessionID: systemMediaSessionID, rate: playbackRate
            )
        case .buffering(let buffering):
            isBuffering = buffering
            if buffering { reporting.interrupt() }
            if !hasRenderedFirstFrame { isLoading = true }
        case .position(let position):
            guard hasRenderedFirstFrame, !isLoading, (!isSwitchingQuality || isFetchingQuality),
                  resumeState.accept(position: position) else { return }
            // MPVEngine limits progress delivery before dispatching to the main queue.
            if isPlaying && !isBuffering { reporting.noteActivePosition() }
            currentTime = position
            reporting.startPlayerBehaviorIfReady(context: reportingContext)
            danmaku?.update(currentTime: position)
            if abs(position - lastSavedPosition) >= 5 { savePlaybackProgress() }
            let checkpoint = reporting.observe(
                position: position, isActive: isPlaying && !isBuffering,
                isMiniPlayer: session.surfacePresentation == .mini
            )
            reporting.startWatchReportIfReady(context: reportingContext)
            reporting.enqueueWatchReport(checkpoint, context: reportingContext)
            dependencies.systemMedia.updateElapsed(
                position,
                sessionID: systemMediaSessionID
            )
        case .seekCompleted(let position):
            guard hasRenderedFirstFrame, !isLoading, (!isSwitchingQuality || isFetchingQuality),
                  resumeState.confirm(position: position) else { return }
            currentTime = position
            // Decoding the requested frame confirms a seek, not watched time.
            reporting.interrupt()
            savePlaybackProgress()
            dependencies.systemMedia.updateElapsed(position, sessionID: systemMediaSessionID, force: true)
        case .duration(let duration):
            if duration.isFinite, duration > 0 {
                self.duration = duration
                dependencies.systemMedia.updateDuration(
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
            endTemporaryDoubleSpeed()
            isLoading = false
            danmaku?.setPaused(true)
            resumeState.complete()
            savePlaybackProgress()
            // Final App history is carried by finish, not a second checkpoint.
            reporting.complete(duration: duration)
            reporting.finishPlayerBehavior(context: reportingContext)
            reporting.finishWatchReport(context: reportingContext)
            if sleepsAfterVideoEnd {
                enterSleep()
            }
            dependencies.systemMedia.updatePlaybackState(
                isPlaying: false,
                sessionID: systemMediaSessionID, rate: playbackRate
            )
        case .error(let message):
            recoverFromSourceFailure(message)
        }
    }

    func updateWatchAid(_ aid: Int) { reporting.updateWatchAid(aid, context: reportingContext) }

    private var reportingContext: PlaybackReportingCoordinator.Context {
        .init(currentTime: currentTime, duration: duration, selectedVideoQuality: selectedVideoQuality,
              playbackRate: playbackRate, isPage: session.surfacePresentation == .page,
              isStopped: isStopped, hasRenderedFirstFrame: hasRenderedFirstFrame,
              isLoading: isLoading, isPlaying: isPlaying)
    }
}
