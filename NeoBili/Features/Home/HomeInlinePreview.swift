import Foundation
import Observation

/// One silent surface for the visible home card. It never joins Now Playing,
/// requests audio focus or treats manifest prefetch as watched playback.
@MainActor @Observable
final class HomeInlinePreview {
    private(set) var videoID: String?
    private(set) var session: MPVPlayerSession?
    private(set) var hasFirstFrame = false
    private(set) var progress = 0.0
    private(set) var duration = 0.0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var ownerID = UUID()
    @ObservationIgnored private var accountSession = UUID()
    @ObservationIgnored private var current: VideoSummary?
    @ObservationIgnored private var cid = 0
    @ObservationIgnored private var playbackSession = ""
    @ObservationIgnored private var localStart = 0
    @ObservationIgnored private var isPlaying = false
    @ObservationIgnored private var buffering = false
    @ObservationIgnored private var watch = PlaybackWatchProgress()
    @ObservationIgnored private var reportSender: PlaybackWatchReportSender?
    @ObservationIgnored private var sentWatchStart = false
    @ObservationIgnored private var playerBehaviorSequence = 0
    @ObservationIgnored private var sentPlayerStart = false
    @ObservationIgnored private var finished = false
    @ObservationIgnored private let loadSource: @Sendable (VideoSummary, UUID, UUID) async throws -> (Int, PlaybackSource)
    @ObservationIgnored private let clock: () -> TimeInterval
    @ObservationIgnored private let injectedReporter: (@Sendable (PlaybackWatchReport) async -> Void)?
    @ObservationIgnored private let openSource: @MainActor (MPVPlayerSession, PlaybackSource) async throws -> Void
    @ObservationIgnored private let makeSession: @MainActor (VideoPlaybackConfiguration) -> MPVPlayerSession

    init(loader: @escaping @Sendable (VideoSummary, UUID, UUID) async throws -> (Int, PlaybackSource) = { video, owner, account in
        guard !AppNetwork.isRegression else { throw CancellationError() }
        return try await HomeInlinePreview.loadPreviewSource(video, owner: owner, account: account)
    }, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         reporter: (@Sendable (PlaybackWatchReport) async -> Void)? = nil,
         opener: @escaping @MainActor (MPVPlayerSession, PlaybackSource) async throws -> Void = { try await $0.open(source: $1) },
         sessionFactory: @escaping @MainActor (VideoPlaybackConfiguration) -> MPVPlayerSession = { MPVPlayerSession(configuration: $0) }) {
        loadSource = loader; self.clock = clock; injectedReporter = reporter; openSource = opener
        makeSession = sessionFactory
    }

    nonisolated static func loadPreviewSource(_ video: VideoSummary, owner: UUID, account: UUID,
                                             cache: VideoPreparationCache = .shared) async throws -> (Int, PlaybackSource) {
        let cid: Int
        if video.cid > 0 { cid = video.cid }
        else { cid = try await cache.detail(for: video.bvid).cid }
        try Task.checkCancellation()
        let payload = try await withTaskCancellationHandler {
            try await cache.playbackURL(bvid: video.bvid, cid: cid,
                                        ownerID: owner, expectedSessionID: account)
        } onCancel: {
            // The card can omit CID; cancel the resolved request, not (bvid, 0).
            Task { await cache.cancelPlaybackURL(bvid: video.bvid, cid: cid,
                                                 ownerID: owner, sessionID: account) }
        }
        try Task.checkCancellation()
        var config = VideoPlaybackConfiguration.fastStart; config.quality = 32
        return (cid, try PlaybackSourceBuilder.makeSource(from: payload, configuration: config))
    }

    func select(_ video: VideoSummary) {
        guard video.isLargeRecommendationCard, video.recommendationTarget == nil else { stop(); return }
        let account = DeviceIdentity.shared.loginSessionID
        guard video.playbackEntry.loginSessionID == nil || video.playbackEntry.loginSessionID == account else { stop(); return }
        if videoID == video.bvid, accountSession == account, current?.playbackEntry == video.playbackEntry { return }
        stop()
        current = video; videoID = video.bvid; accountSession = account
        cid = video.cid
        requestID = UUID(); ownerID = UUID()
        playbackSession = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let id = requestID, owner = ownerID, loader = loadSource
        task = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
                let (cid, source) = try await loader(video, owner, account)
                try Task.checkCancellation()
                guard let self, self.requestID == id, DeviceIdentity.shared.loginSessionID == account else { return }
                // Publishing a session mounts PlayerSurface and initializes mpv,
                // even before its first frame is visible. Keep that work behind
                // both the dwell threshold and the cancellable manifest load.
                var configuration = VideoPlaybackConfiguration.fastStart
                configuration.quality = 32; configuration.silentPreview = true
                configuration.maxBufferBytes = 8 * 1024 * 1024; configuration.maxBackBufferBytes = 0
                let surface = self.makeSession(configuration)
                self.session = surface
                surface.onEvent = { [weak self, weak surface] event in
                    guard let self, let surface, self.session === surface else { return }
                    self.handle(event)
                }
                self.cid = cid; self.duration = source.duration
                if let reporter = self.injectedReporter { self.reportSender = PlaybackWatchReportSender(report: reporter) }
                else {
                    self.reportSender = .shared(loginSessionID: account, bvid: video.bvid, cid: cid, serverReport: { report in
                        try? await BiliAPI.reportAppWatch(bvid: video.bvid, aid: video.aid, cid: cid, report: report, expectedSessionID: account)
                    })
                }
                try await self.openSource(surface, source)
            } catch {
                guard let self, self.requestID == id else { return }
                self.session?.stop(); self.session = nil
            }
        }
    }

    func stop() {
        // Visibility is evaluated on every scroll callback. Once fully idle,
        // there is no generation to invalidate or observable state to reset.
        guard current != nil || task != nil || session != nil || videoID != nil
                || sentWatchStart || sentPlayerStart else { return }
        if let video = current {
            finish()
            let owner = ownerID, account = accountSession, resolvedCID = cid
            Task { await VideoPreparationCache.shared.cancelPlaybackURL(bvid: video.bvid, cid: resolvedCID,
                ownerID: owner, sessionID: account) }
        }
        requestID = UUID(); task?.cancel(); task = nil
        session?.onEvent = nil; session?.stop(); session = nil
        videoID = nil; current = nil; progress = 0; duration = 0; hasFirstFrame = false
        watch = PlaybackWatchProgress(); sentWatchStart = false; sentPlayerStart = false; finished = false
        isPlaying = false; buffering = false; reportSender = nil
        playerBehaviorSequence = 0
    }

    private func handle(_ event: PlayerPlaybackEvent) {
        guard !finished, accountSession == DeviceIdentity.shared.loginSessionID else { return }
        switch event {
        case .firstFrame: hasFirstFrame = true
        case .playing(let value):
            let changed = isPlaying != value
            watch.setPaused(!value, at: clock()); isPlaying = value
            if sentPlayerStart, changed { behavior(value ? "player.player.resume.all.player" : "player.player.pause.all.player") }
            if !value { watch.interrupt() }
        case .buffering(let value): buffering = value; if value { watch.interrupt() }
        case .position(let position):
            guard hasFirstFrame, isPlaying, !buffering, position.isFinite, position >= 0 else { return }
            progress = position
            if !sentPlayerStart { sentPlayerStart = true; localStart = Int(Date().timeIntervalSince1970); behavior("player.player.start.all.player") }
            let checkpoint = watch.observe(position: position, at: clock(), isActive: true)
            if !sentWatchStart, watch.watchedTime > 0 {
                sentWatchStart = true
                reportSender?.enqueue(report(.start, position: 0))
            }
            if let checkpoint { reportSender?.enqueue(report(.checkpoint, position: checkpoint)) }
        case .duration(let value): if value.isFinite, value > 0 { duration = value }
        case .ended: _ = watch.complete(duration: duration); finish()
        case .error: finish(); session?.stop(); session = nil
        default: break
        }
    }

    private func report(_ delivery: PlaybackWatchReport.Delivery, position: Double) -> PlaybackWatchReport {
        var fields = current?.playbackEntry.parameters(for: accountSession) ?? [:]
        fields["from"] = "76"; fields["from_spmid"] = "tm.recommend.0.0"; fields["spmid"] = "tm.recommend.0.0"
        var value = watch.report(position: position, duration: duration, startTimestamp: 0, sourceFields: fields, at: clock())
        value.playbackSession = playbackSession; value.aid = current?.aid ?? 0
        value.delivery = delivery; value.localStartTimestamp = localStart; value.isInlinePreview = true
        if delivery == .start {
            value = PlaybackWatchReport(position: 0, watchedTime: 0, pausedTime: 0, maximumPosition: 0, duration: duration,
                startTimestamp: 0, sourceFields: fields, playbackSession: playbackSession, aid: current?.aid ?? 0,
                delivery: .start, localStartTimestamp: localStart, isInlinePreview: true)
        }
        return value
    }

    private func finish() {
        guard !finished else { return }
        if sentWatchStart, let position = watch.terminalPosition { reportSender?.enqueue(report(.finish, position: position)) }
        if sentPlayerStart { behavior("player.player.end.all.player") }
        finished = true
    }

    private func behavior(_ name: String) {
        AppPlayerBehavior.record(name, aid: current?.aid ?? 0, cid: cid, position: progress,
            playbackSession: playbackSession, source: ["from_spmid":"tm.recommend.0.0","track_id":current?.playbackEntry.trackID ?? ""],
            accountSession: accountSession, quality: nil, sequence: playerBehaviorSequence, inlinePreview: true)
        playerBehaviorSequence += 1
    }
}
