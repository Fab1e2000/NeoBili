import Foundation

@main
@MainActor
struct PlaybackWatchProgressRegression {
    private static var assertions = 0

    @MainActor
    static func main() async {
        testUnwatchedPositionsNeverUpload()
        testHeartbeatCadenceAndPlaybackRates()
        testSeekAndBufferDiscontinuities()
        testCompletionEvidence()
        await testSlowSenderCoalescesInOrder()
        await testReopenedPlayerSharesOnlyItsOwnWriter()
        print("Playback watch progress regression passed: \(assertions) assertions; first heartbeat 5 s, then 15 s, pause/exit flush, seek/preload/buffering/EOF guards, 0.5x/2x, serialized coalescing")
    }

    @MainActor
    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        if !condition() { fatalError(message) }
    }

    @MainActor
    private static func testUnwatchedPositionsNeverUpload() {
        var progress = PlaybackWatchProgress()
        expect(progress.checkpoint() == nil, "closing a preloaded player must not upload")
        expect(progress.observe(position: 90, at: 0, isActive: false) == nil, "saved position is not watching")
        expect(progress.checkpoint() == nil, "pausing a saved position must not upload")
        expect(progress.observe(position: 90, at: 1, isActive: true) == nil, "first decoded frame is not watching")
        expect(progress.checkpoint() == nil, "one frame does not prove progress")
        progress.interrupt(discontinuity: true)
        expect(progress.observe(position: 120, at: 2, isActive: false) == nil, "paused seek is not watching")
        expect(progress.complete(duration: 120) == nil, "seek to EOF must not mark completed")
    }

    @MainActor
    private static func testHeartbeatCadenceAndPlaybackRates() {
        for rate in [0.5, 1.0, 2.0] {
            var progress = PlaybackWatchProgress()
            var reports: [Double] = []
            for tick in 0...140 {
                let time = Double(tick) / 4
                if let report = progress.observe(position: time * rate, at: time, isActive: true) {
                    reports.append(report)
                }
            }
            expect(reports == [floor(5 * rate), floor(20 * rate), floor(35 * rate)],
                   "heartbeat cadence must follow real viewing time at rate \(rate): \(reports)")
            expect(progress.checkpoint() == nil, "repeated pause must not duplicate the last second")
        }
        var short = PlaybackWatchProgress()
        _ = short.observe(position: 0, at: 0, isActive: true)
        _ = short.observe(position: 1.75, at: 1.75, isActive: true)
        expect(short.checkpoint() == 1, "short real viewing must flush on pause without rounding ahead")
        expect(short.checkpoint() == nil, "stop after pause must not duplicate")
    }

    @MainActor
    private static func testSeekAndBufferDiscontinuities() {
        var progress = PlaybackWatchProgress()
        _ = progress.observe(position: 0, at: 0, isActive: true)
        _ = progress.observe(position: 2, at: 2, isActive: true)
        expect(progress.checkpoint() == 2, "seek first flushes only the last watched position")
        progress.interrupt(discontinuity: true)
        _ = progress.observe(position: 119.9, at: 2.1, isActive: true)
        expect(progress.checkpoint() == nil, "jump target does not upload")
        expect(progress.complete(duration: 120) == nil, "jump target does not complete")

        progress = PlaybackWatchProgress()
        _ = progress.observe(position: 0, at: 0, isActive: true)
        _ = progress.observe(position: 100, at: 0.25, isActive: true)
        expect(progress.checkpoint() == nil, "unannounced large position discontinuity does not count")
        _ = progress.observe(position: 110, at: 10, isActive: false)
        _ = progress.observe(position: 112, at: 12, isActive: true)
        expect(progress.checkpoint() == nil, "buffer recovery establishes a fresh baseline")
        _ = progress.observe(position: 113, at: 13, isActive: true)
        expect(progress.checkpoint() == 113, "normal playback after buffering may report")
        progress.interrupt(discontinuity: true)
        _ = progress.observe(position: 20, at: 14, isActive: true)
        _ = progress.observe(position: 21, at: 15, isActive: true)
        expect(progress.checkpoint() == 21, "backward seek followed by real playback updates history")
        progress.interrupt(discontinuity: true)
        _ = progress.observe(position: 21, at: 16, isActive: true)
        _ = progress.observe(position: 40, at: 35, isActive: true)
        expect(progress.checkpoint() == nil, "suspended callback gaps are not continuous viewing")
    }

    @MainActor
    private static func testCompletionEvidence() {
        var progress = PlaybackWatchProgress()
        for tick in 0...11 {
            let position = Double(tick) / 4
            _ = progress.observe(position: position, at: position, isActive: true)
        }
        expect(progress.complete(duration: 3) == 2, "EOF too far from a short video's end only reports progress")
        expect(progress.complete(duration: 3) == nil, "repeated EOF is idempotent")

        progress = PlaybackWatchProgress()
        for tick in 0...12 {
            let position = Double(tick) / 4
            _ = progress.observe(position: position, at: position, isActive: true)
        }
        progress.interrupt() // mpv may deliver playing(false) before EOF.
        expect(progress.complete(duration: 3) == -1, "genuinely completed short video must upload before 5 s")
        expect(progress.checkpoint() == nil, "stop after completion must not revert completed history")
        progress.interrupt(discontinuity: true)
        _ = progress.observe(position: 0, at: 4, isActive: true)
        _ = progress.observe(position: 1, at: 5, isActive: true)
        expect(progress.checkpoint() == 1, "replaying the same video starts a new watched segment")

        progress = PlaybackWatchProgress()
        _ = progress.observe(position: 0, at: 0, isActive: true)
        _ = progress.observe(position: 2, at: 2, isActive: true)
        expect(progress.complete(duration: 0) == 2, "unknown duration cannot prove completion")
        progress = PlaybackWatchProgress()
        _ = progress.observe(position: .infinity, at: 0, isActive: true)
        _ = progress.observe(position: .nan, at: 1, isActive: true)
        expect(progress.checkpoint() == nil, "nonfinite engine values never upload")
    }

    @MainActor
    private static func testSlowSenderCoalescesInOrder() async {
        let recorder = SlowRecorder()
        let sender = PlaybackWatchProgressSender { await recorder.report($0) }
        sender.enqueue(5)
        await recorder.waitForCount(1)
        for value in 6...100 { sender.enqueue(Double(value)) }
        sender.enqueue(-1)
        await recorder.releaseFirst()
        await recorder.waitForCount(2)
        let values = await recorder.values
        expect(values == [5, -1], "slow network must preserve order and coalesce intermediate checkpoints: \(values)")
    }

    @MainActor
    private static func testReopenedPlayerSharesOnlyItsOwnWriter() async {
        let recorder = SlowRecorder()
        let login = UUID()
        var old: PlaybackWatchProgressSender? = .shared(loginSessionID: login, bvid: "same", cid: 1) {
            await recorder.report($0)
        }
        let previous = ObjectIdentifier(old!)
        old?.enqueue(55)
        await recorder.waitForCount(1)
        old?.enqueue(60)
        old = nil // The old video page can be fully released during the request.
        let reopened = PlaybackWatchProgressSender.shared(loginSessionID: login, bvid: "same", cid: 1) {
            await recorder.report($0)
        }
        expect(ObjectIdentifier(reopened) == previous, "reopening same part must retain the in-flight writer")
        reopened.enqueue(65)
        await recorder.releaseFirst()
        await recorder.waitForCount(2)
        let values = await recorder.values
        expect(values == [55, 65], "new actual progress must replace pending old progress, never race it: \(values)")
        let otherPart = PlaybackWatchProgressSender.shared(loginSessionID: login, bvid: "same", cid: 2) { _ in }
        let otherVideo = PlaybackWatchProgressSender.shared(loginSessionID: login, bvid: "other", cid: 1) { _ in }
        let otherLogin = PlaybackWatchProgressSender.shared(loginSessionID: UUID(), bvid: "same", cid: 1) { _ in }
        expect(otherPart !== reopened, "different parts must not replace each other's pending progress")
        expect(otherVideo !== reopened, "different videos must not share writers")
        expect(otherLogin !== reopened, "different login sessions must not share writers")
        weak var released: PlaybackWatchProgressSender?
        do {
            let unused = PlaybackWatchProgressSender.shared(loginSessionID: login, bvid: "unused", cid: 1) { _ in }
            released = unused
        }
        expect(released == nil, "registry must not retain idle closed players")
    }
}

private actor SlowRecorder {
    private(set) var values: [Double] = []
    private var first: CheckedContinuation<Void, Never>?
    private var waiter: (Int, CheckedContinuation<Void, Never>)?

    func report(_ value: Double) async {
        values.append(value)
        if values.count == 1 {
            await withCheckedContinuation { first = $0; notify() }
        } else {
            notify()
        }
    }

    func waitForCount(_ count: Int) async {
        if values.count >= count { return }
        await withCheckedContinuation { waiter = (count, $0) }
    }

    func releaseFirst() {
        first?.resume()
        first = nil
    }

    private func notify() {
        guard let (count, continuation) = waiter, values.count >= count else { return }
        waiter = nil
        continuation.resume()
    }
}
