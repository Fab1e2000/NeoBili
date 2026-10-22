#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation

/// Owns reporting state, never the player or its rendering session.
@MainActor
final class PlaybackReportingCoordinator {
    struct Context {
        let currentTime: Double
        let duration: Double
        let selectedVideoQuality: Int?
        let playbackRate: Double
        let isPage: Bool
        let isStopped: Bool
        let hasRenderedFirstFrame: Bool
        let isLoading: Bool
        let isPlaying: Bool
    }

    private let telemetry: TelemetryService
    private let cid: Int
    private let loginSessionID: UUID
    private let watchProgressSender: PlaybackWatchProgressSender?
    private let watchReportSender: PlaybackWatchReportSender?
    private let playbackEntry: PlaybackEntry
    private var watchStartTimestamp: Int?
    private var watchPlaybackSession: String
    private var hasSentWatchStart = false
    private var hasSentWatchFinish = false
    private var hasSentPlayerStart = false
    private var hasSentPlayerEnd = false
    private var lastLoggedPlaying: Bool?
    private var watchAid: Int
    private let watchProgressClock: () -> TimeInterval
    private var watchProgress = PlaybackWatchProgress()

    init(telemetry: TelemetryService, cid: Int, loginSessionID: UUID,
         playbackEntry: PlaybackEntry, playbackSession: String, aid: Int,
         clock: @escaping () -> TimeInterval,
         progressSender: PlaybackWatchProgressSender?, reportSender: PlaybackWatchReportSender?) {
        self.telemetry = telemetry
        self.cid = cid
        self.loginSessionID = loginSessionID
        self.playbackEntry = playbackEntry
        self.watchPlaybackSession = playbackSession
        self.watchAid = aid
        self.watchProgressClock = clock
        self.watchProgressSender = progressSender
        self.watchReportSender = reportSender
    }

    func setPlaybackRate(_ rate: Double) { watchProgress.setPlaybackRate(rate, at: watchProgressClock()) }
    func setPaused(_ paused: Bool) { watchProgress.setPaused(paused, at: watchProgressClock()) }
    func interrupt(discontinuity: Bool = false) { watchProgress.interrupt(discontinuity: discontinuity) }

    func noteActivePosition() {
        if watchStartTimestamp == nil { watchStartTimestamp = Int(Date().timeIntervalSince1970) }
    }

    func observe(position: Double, isActive: Bool, isMiniPlayer: Bool) -> Double? {
        watchProgress.observe(position: position, at: watchProgressClock(), isActive: isActive,
                              isMiniPlayer: isMiniPlayer)
    }

    func enqueueLegacyCheckpoint() { watchProgressSender?.enqueue(watchProgress.checkpoint()) }

    func complete(duration: Double) {
        let terminal = watchProgress.complete(duration: duration)
        watchProgressSender?.enqueue(terminal)
    }

    func recordPlayingTransition(_ playing: Bool, context: Context) {
        if hasSentPlayerStart, lastLoggedPlaying != playing {
            recordPlayerBehavior(playing ? "player.player.resume.all.player" : "player.player.pause.all.player",
                                 context: context)
            lastLoggedPlaying = playing
        }
    }

    func updateWatchAid(_ aid: Int, context: Context) {
        if aid > 0 {
            watchAid = aid
            startPlayerBehaviorIfReady(context: context)
            startWatchReportIfReady(context: context)
        }
    }

    func startWatchReportIfReady(context: Context) {
        guard !context.isStopped, watchReportSender != nil, watchAid > 0,
              watchProgress.watchedTime > 0, !hasSentWatchStart else { return }
        hasSentWatchStart = true
        startPlayerBehaviorIfReady(context: context)
        let snapshot = makeWatchReport(position: 0, context: context)
        let start = PlaybackWatchReport(position: 0, watchedTime: 0, pausedTime: 0,
            maximumPosition: 0, duration: context.duration, startTimestamp: 0,
            sourceFields: snapshot.sourceFields, playbackSession: watchPlaybackSession,
            aid: watchAid, delivery: .start)
        watchReportSender?.enqueue(start)
    }

    func enqueueWatchReport(_ position: Double?, context: Context) {
        guard let position else { return }
        watchProgressSender?.enqueue(position)
        var report = makeWatchReport(position: position, context: context)
        report.delivery = .checkpoint
        watchReportSender?.enqueue(report)
    }

    private func makeWatchReport(position: Double, context: Context) -> PlaybackWatchReport {
        var fields = playbackEntry.parameters(for: loginSessionID)
        if let selectedVideoQuality = context.selectedVideoQuality { fields["quality"] = String(selectedVideoQuality) }
        if context.isPage { fields["spmid"] = "united.player-video-detail.0.0" }
        var report = watchProgress.report(position: position, duration: context.duration,
            startTimestamp: watchStartTimestamp ?? Int(Date().timeIntervalSince1970), sourceFields: fields, at: watchProgressClock())
        report.playbackSession = watchPlaybackSession
        report.aid = watchAid
        report.localStartTimestamp = watchStartTimestamp
        report.startTimestamp = 0 // Sender fills only the acknowledgement for this playback session.
        return report
    }

    func finishWatchReport(context: Context) {
        guard hasSentWatchStart, !hasSentWatchFinish, let position = watchProgress.terminalPosition else { return }
        hasSentWatchFinish = true
        finishPlayerBehavior(context: context)
        var report = makeWatchReport(position: position, context: context)
        report.delivery = .finish
        watchReportSender?.enqueue(report)
    }

    func resetWatchReport(context: Context) {
        watchProgress = PlaybackWatchProgress()
        watchProgress.setPlaybackRate(context.playbackRate, at: watchProgressClock())
        watchStartTimestamp = nil
        watchPlaybackSession = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        hasSentWatchStart = false
        hasSentWatchFinish = false
        hasSentPlayerStart = false
        hasSentPlayerEnd = false
        lastLoggedPlaying = nil
        playerBehaviorSequence = 0
    }

    private var playerBehaviorSequence = 0

    private func recordPlayerBehavior(_ name: String, position: Double? = nil, context: Context) {
        telemetry.record(name, aid: watchAid, cid: cid, position: position ?? context.currentTime,
            playbackSession: watchPlaybackSession, source: playbackEntry.parameters(for: loginSessionID),
            accountSession: loginSessionID, quality: context.selectedVideoQuality, playbackRate: context.playbackRate, sequence: playerBehaviorSequence)
        playerBehaviorSequence += 1
    }

    func startPlayerBehaviorIfReady(context: Context) {
        guard !context.isStopped, watchAid > 0, context.hasRenderedFirstFrame, !context.isLoading, context.isPlaying,
              !hasSentPlayerStart else { return }
        hasSentPlayerStart = true; hasSentPlayerEnd = false
        lastLoggedPlaying = true
        recordPlayerBehavior("player.player.start.all.player", position: 0, context: context)
    }

    func finishPlayerBehavior(context: Context) {
        guard hasSentPlayerStart, !hasSentPlayerEnd else { return }
        hasSentPlayerEnd = true
        recordPlayerBehavior("player.player.end.all.player", context: context)
    }

    /// 观看进度上报（心跳）。失败静默：历史记录是尽力而为的副产品，
    /// 不能因为上报失败打断或提示播放。
    func checkpointWatchProgress(context: Context) {
        enqueueWatchReport(watchProgress.checkpoint(), context: context)
    }
}
