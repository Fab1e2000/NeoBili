import Foundation

/// Watching is confirmed by consecutive, advancing decoder positions while the
/// player is active. A resume point, seek target or first frame alone is not a view.
struct PlaybackWatchProgress {
    private struct Sample {
        let position: TimeInterval
        let time: TimeInterval
    }

    private var sample: Sample?
    private var lastWatchedPosition: TimeInterval?
    private var watchedSinceReport: TimeInterval = 0
    private var lastReportedSecond: Int?
    private var segmentHasProgress = false
    private var isCompleted = false
    var terminalPosition: Double? { lastReportedSecond == -1 ? -1 : lastWatchedPosition }
    private(set) var watchedTime: TimeInterval = 0
    private(set) var maximumPosition: TimeInterval = 0
    private(set) var miniPlayerTime: TimeInterval = 0
    private(set) var pausedTime: TimeInterval = 0
    private var pauseStarted: TimeInterval?

    /// History checkpoint after five real seconds, then every fifteen seconds.
    /// Explicit pause/exit may flush a shorter, actually watched segment.
    mutating func observe(position: TimeInterval, at time: TimeInterval, isActive: Bool, isMiniPlayer: Bool = false) -> Double? {
        guard !isCompleted, isActive, position.isFinite, position >= 0, time.isFinite else {
            sample = nil
            return nil
        }
        let previous = sample
        sample = Sample(position: position, time: time)
        guard let previous else { return nil }
        let elapsed = time - previous.time
        let advanced = position - previous.position
        // mpv normally samples several times a second. Do not interpret an app
        // suspension or a discontinuous timestamp as uninterrupted viewing.
        // The bound permits playback from 0.5x through 4x without counting seeks.
        guard elapsed > 0, elapsed <= 3, advanced > 0,
              advanced <= elapsed * 4 + 0.25 else { return nil }
        setPaused(false, at: time)
        watchedTime += elapsed
        if isMiniPlayer { miniPlayerTime += elapsed }
        maximumPosition = max(maximumPosition, position)
        lastWatchedPosition = position
        segmentHasProgress = true
        watchedSinceReport += elapsed
        let interval: TimeInterval = lastReportedSecond == nil ? 5 : 15
        return watchedSinceReport >= interval ? checkpoint() : nil
    }

    mutating func setPaused(_ paused: Bool, at time: TimeInterval) {
        guard time.isFinite else { return }
        if paused {
            guard watchedTime > 0 else { return }
            if pauseStarted == nil { pauseStarted = time }
        } else if let start = pauseStarted {
            pausedTime += max(0, time - start)
            pauseStarted = nil
        }
    }

    func report(position: Double, duration: Double, startTimestamp: Int,
                sourceFields: [String: String], at time: TimeInterval) -> PlaybackWatchReport {
        let pause = pausedTime + (pauseStarted.map { max(0, time - $0) } ?? 0)
        var report = PlaybackWatchReport(position: position, watchedTime: watchedTime,
            pausedTime: pause, maximumPosition: maximumPosition, duration: duration,
            startTimestamp: startTimestamp, sourceFields: sourceFields)
        report.miniPlayerTime = miniPlayerTime
        return report
    }

    /// Pause/buffering breaks the timing baseline. Seeking or replacing a source
    /// additionally invalidates completion evidence from the previous segment.
    mutating func interrupt(discontinuity: Bool = false) {
        sample = nil
        if discontinuity {
            segmentHasProgress = false
            isCompleted = false
        }
    }

    mutating func checkpoint() -> Double? {
        guard watchedSinceReport > 0, let position = lastWatchedPosition,
              position < Double(Int.max) else { return nil }
        let second = Int(position.rounded(.down))
        guard second > 0, second != lastReportedSecond else { return nil }
        lastReportedSecond = second
        watchedSinceReport = 0
        return Double(second)
    }

    /// EOF alone can also be caused by an empty/truncated stream or seeking to
    /// its end. Only real progress in the final segment may mark it completed.
    mutating func complete(duration: TimeInterval) -> Double? {
        sample = nil
        guard !isCompleted else { return nil }
        isCompleted = true
        guard segmentHasProgress, let position = lastWatchedPosition,
              duration.isFinite, duration > 0,
              position >= duration - min(1, duration * 0.05),
              position <= duration + 1 else { return checkpoint() }
        lastReportedSecond = -1
        watchedSinceReport = 0
        return -1
    }
}

/// One history writer per video part and login session. When a slow request is in flight, newer
/// checkpoints replace the pending one rather than creating more network tasks.
/// Keeping this separate lets the final checkpoint finish after the player exits.
@MainActor
final class PlaybackWatchProgressSender {
    private struct Key: Hashable {
        let loginSessionID: UUID
        let bvid: String
        let cid: Int
    }

    private final class WeakReference {
        weak var value: PlaybackWatchProgressSender?
        init(_ value: PlaybackWatchProgressSender) { self.value = value }
    }

    private static var sharedSenders: [Key: WeakReference] = [:]

    /// Reopening the same part must join its old writer while the last request
    /// is still in flight. Otherwise that request can overwrite newer history.
    /// Only live reporters use this registry; injected test reporters stay local.
    static func shared(loginSessionID: UUID, bvid: String, cid: Int,
                       report: @escaping @Sendable (Double) async -> Void) -> PlaybackWatchProgressSender {
        sharedSenders = sharedSenders.filter { $0.value.value != nil }
        let key = Key(loginSessionID: loginSessionID, bvid: bvid, cid: cid)
        if let existing = sharedSenders[key]?.value { return existing }
        let sender = PlaybackWatchProgressSender(report: report)
        sharedSenders[key] = WeakReference(sender)
        return sender
    }

    private let report: @Sendable (Double) async -> Void
    private var pending: Double?
    private var task: Task<Void, Never>?

    init(report: @escaping @Sendable (Double) async -> Void) {
        self.report = report
    }

    func enqueue(_ position: Double?) {
        guard let position else { return }
        pending = position
        guard task == nil else { return }
        task = Task {
            while let position = pending {
                pending = nil
                await report(position)
            }
            task = nil
        }
    }
}

/// 移动心跳的观看秒数与历史进度分开；不能把续播/拖动位置当成观看时长。
struct PlaybackWatchReport: Sendable {
    enum Delivery: Sendable, Equatable { case start, checkpoint, finish }
    let position: Double
    let watchedTime: Double
    let pausedTime: Double
    let maximumPosition: Double
    let duration: Double
    var startTimestamp: Int
    let sourceFields: [String: String]
    var playbackSession: String = ""
    var aid: Int = 0
    var miniPlayerTime: Double = 0
    var delivery: Delivery = .finish
    var localStartTimestamp: Int? = nil
    var isInlinePreview = false

}

@MainActor
final class PlaybackWatchReportSender {
    private struct Key: Hashable {
        let loginSessionID: UUID
        let bvid: String
        let cid: Int
    }

    private final class WeakReference {
        weak var value: PlaybackWatchReportSender?
        init(_ value: PlaybackWatchReportSender) { self.value = value }
    }

    private static var sharedSenders: [Key: WeakReference] = [:]

    /// Reopening the same part must join its old writer while the last request
    /// is still in flight. Otherwise that request can overwrite newer history.
    /// Only live reporters use this registry; injected test reporters stay local.
    static func shared(loginSessionID: UUID, bvid: String, cid: Int,
                       report: @escaping @Sendable (PlaybackWatchReport) async -> Void) -> PlaybackWatchReportSender {
        sharedSenders = sharedSenders.filter { $0.value.value != nil }
        let key = Key(loginSessionID: loginSessionID, bvid: bvid, cid: cid)
        if let existing = sharedSenders[key]?.value { return existing }
        let sender = PlaybackWatchReportSender(report: report)
        sharedSenders[key] = WeakReference(sender)
        return sender
    }

    private let report: @Sendable (PlaybackWatchReport) async -> Int?
    private var serverTimestamps: [String: Int] = [:]
    private var pending: [PlaybackWatchReport] = []
    private var task: Task<Void, Never>?

    init(report: @escaping @Sendable (PlaybackWatchReport) async -> Void) {
        self.report = { value in await report(value); return nil }
    }

    init(serverReport: @escaping @Sendable (PlaybackWatchReport) async -> Int?, receivesAcknowledgements: Bool) {
        self.report = serverReport
    }

    static func shared(loginSessionID: UUID, bvid: String, cid: Int,
                       serverReport: @escaping @Sendable (PlaybackWatchReport) async -> Int?) -> PlaybackWatchReportSender {
        sharedSenders = sharedSenders.filter { $0.value.value != nil }
        let key = Key(loginSessionID: loginSessionID, bvid: bvid, cid: cid)
        if let existing = sharedSenders[key]?.value { return existing }
        let sender = PlaybackWatchReportSender(serverReport: serverReport, receivesAcknowledgements: true)
        sharedSenders[key] = WeakReference(sender)
        return sender
    }

    func enqueue(_ position: PlaybackWatchReport?) {
        guard let position else { return }
        // Start/finish are session boundaries. Never coalesce them across re-entry.
        // Only replace adjacent history checkpoints from the same playback session.
        if position.delivery == .checkpoint, let last = pending.last,
           last.delivery == .checkpoint, last.playbackSession == position.playbackSession {
            pending[pending.count - 1] = position
        } else {
            pending.append(position)
        }
        guard task == nil else { return }
        task = Task {
            while !pending.isEmpty {
                var position = pending.removeFirst()
                if position.delivery != .start, let timestamp = serverTimestamps[position.playbackSession] {
                    position.startTimestamp = timestamp
                }
                let timestamp = await report(position)
                if position.delivery == .start, let timestamp, timestamp > 0 {
                    serverTimestamps[position.playbackSession] = timestamp
                }
                if position.delivery == .finish { serverTimestamps.removeValue(forKey: position.playbackSession) }
            }
            task = nil
        }
    }
}
