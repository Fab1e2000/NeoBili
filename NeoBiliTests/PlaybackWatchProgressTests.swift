import XCTest
@testable import NeoBili

@MainActor
final class PlaybackWatchProgressTests: XCTestCase {
    func testPlaybackRatesCountRealElapsedTimeAndDoNotCountSeekJump() {
        for rate in PlaybackSpeed.options {
            var progress = PlaybackWatchProgress()
            progress.setPlaybackRate(rate, at: 0)
            _ = progress.observe(position: 0, at: 0, isActive: true)
            for second in 1...10 {
                _ = progress.observe(position: Double(second) * rate, at: Double(second), isActive: true)
            }
            XCTAssertEqual(progress.watchedTime, 10, accuracy: 0.001)
            XCTAssertEqual(progress.maximumPosition, 10 * rate, accuracy: 0.001)
            XCTAssertEqual(progress.actualPlayedTime, 10 * rate, accuracy: 0.001)
            progress.interrupt(discontinuity: true)
            _ = progress.observe(position: 100, at: 11, isActive: true)
            XCTAssertEqual(progress.watchedTime, 10, accuracy: 0.001)
            _ = progress.observe(position: 100 + rate, at: 12, isActive: true)
            XCTAssertEqual(progress.watchedTime, 11, accuracy: 0.001)
        }
    }

    private func makeStore() throws -> PlaybackProgressStore {
        let suite = "neobili.watch-progress.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return PlaybackProgressStore(defaults: defaults)
    }

    func testResumePauseSeekAndStopWithoutWatchingNeverUpload() async throws {
        let report = expectation(description: "unwatched video never reports")
        report.isInverted = true
        let store = try makeStore()
        store.save(bvid: "BVWatchTest", cid: 1, position: 90, duration: 300)
        let player = PlayerViewModel(bvid: "BVWatchTest", cid: 1,
            watchProgressReporter: { _, _, _ in report.fulfill() }, progressStore: store)
        player.pause()
        player.session.onEvent?(.firstFrame)
        player.session.onEvent?(.duration(300))
        await player.seek(to: 300)
        player.session.onEvent?(.seekCompleted(300))
        player.session.onEvent?(.ended)
        player.stop()
        await fulfillment(of: [report], timeout: 0.1)
    }

    func testGenuinelyCompletedShortVideoReportsOnceWithoutLaterRegression() async throws {
        let report = expectation(description: "short video completes")
        let recorder = WatchReportRecorder()
        var clock = 0.0
        let player = PlayerViewModel(bvid: "BVWatchTest", cid: 1,
            watchProgressReporter: { _, _, value in
                await recorder.append(value)
                report.fulfill()
            }, progressStore: try makeStore(), watchProgressClock: { clock })
        player.session.onEvent?(.firstFrame)
        player.session.onEvent?(.duration(3))
        player.session.onEvent?(.playing(true))
        player.session.onEvent?(.position(0))
        for value in [1.0, 2.0, 2.9] {
            clock = value
            player.session.onEvent?(.position(value))
        }
        player.session.onEvent?(.playing(false))
        player.session.onEvent?(.ended)
        player.session.onEvent?(.position(0))
        player.stop()
        await fulfillment(of: [report], timeout: 1)
        let values = await recorder.values
        XCTAssertEqual(values, [-1], "trailing stop/position callbacks cannot overwrite completion")
    }

    func testSeekingOnlyFlushesActuallyWatchedPosition() async throws {
        let report = expectation(description: "pre-seek real progress is flushed")
        let recorder = WatchReportRecorder()
        var clock = 0.0
        let player = PlayerViewModel(bvid: "BVWatchTest", cid: 1,
            watchProgressReporter: { _, _, value in
                await recorder.append(value)
                report.fulfill()
            }, progressStore: try makeStore(), watchProgressClock: { clock })
        player.session.onEvent?(.firstFrame)
        player.session.onEvent?(.duration(300))
        player.session.onEvent?(.playing(true))
        player.session.onEvent?(.position(0))
        clock = 2
        player.session.onEvent?(.position(2))
        await player.seek(to: 290)
        player.session.onEvent?(.seekCompleted(290))
        player.pause()
        player.stop()
        await fulfillment(of: [report], timeout: 1)
        let values = await recorder.values
        XCTAssertEqual(values, [2], "dragging to 290 seconds must not upload 290")
    }

    func testSourceReplacementCannotTurnRestoredPositionIntoWatching() async throws {
        let report = expectation(description: "recovery without actual progress never reports")
        report.isInverted = true
        let payload = PlayURLData(quality: 64, acceptQuality: [64], acceptDescription: nil,
            durl: [DurlItem(url: "https://example.invalid/primary.mp4",
                            backupUrl: ["https://example.invalid/backup.mp4"], length: 300_000, size: nil)],
            dash: nil, vVoucher: nil)
        let store = try makeStore()
        store.save(bvid: "BVWatchTest", cid: 1, position: 90, duration: 300)
        let player = PlayerViewModel(bvid: "BVWatchTest", cid: 1,
            playbackURLLoader: { _, _ in payload },
            watchProgressReporter: { _, _, _ in report.fulfill() }, progressStore: store,
            sourceOpener: { _, _, _ in })
        await player.load()
        let oldCallback = player.session.onEvent
        oldCallback?(.firstFrame)
        oldCallback?(.playing(true))
        oldCallback?(.position(90))
        oldCallback?(.error("retry backup"))
        oldCallback?(.position(95))
        oldCallback?(.ended)
        player.session.onEvent?(.firstFrame)
        player.session.onEvent?(.seekCompleted(90))
        player.stop()
        await fulfillment(of: [report], timeout: 0.1)
    }

    func testReopenedPlayerSerializesOldAndNewHeartbeats() async {
        let firstStarted = expectation(description: "old heartbeat started")
        let latestFinished = expectation(description: "newest heartbeat finishes after old request")
        let recorder = WatchReportRecorder()
        let gate = WatchReportGate()
        let login = UUID()
        var old: PlaybackWatchProgressSender? = .shared(loginSessionID: login, bvid: "same", cid: 1) { value in
            await recorder.append(value)
            if value == 55 {
                firstStarted.fulfill()
                await gate.wait()
            } else {
                latestFinished.fulfill()
            }
        }
        old?.enqueue(55)
        await fulfillment(of: [firstStarted], timeout: 1)
        old?.enqueue(60)
        old = nil
        let reopened = PlaybackWatchProgressSender.shared(loginSessionID: login, bvid: "same", cid: 1) { _ in
            XCTFail("the old in-flight writer should have been reused")
        }
        reopened.enqueue(65)
        await gate.release()
        await fulfillment(of: [latestFinished], timeout: 1)
        let values = await recorder.values
        XCTAssertEqual(values, [55, 65], "old pending 60 must not overwrite the reopened player's 65")
    }

    func testHeartbeatWritersSeparatePartsAndLoginsAndDoNotRetainIdlePlayers() {
        let login = UUID()
        let first = PlaybackWatchProgressSender.shared(loginSessionID: login, bvid: "same", cid: 1) { _ in }
        let same = PlaybackWatchProgressSender.shared(loginSessionID: login, bvid: "same", cid: 1) { _ in }
        let otherPart = PlaybackWatchProgressSender.shared(loginSessionID: login, bvid: "same", cid: 2) { _ in }
        let otherLogin = PlaybackWatchProgressSender.shared(loginSessionID: UUID(), bvid: "same", cid: 1) { _ in }
        XCTAssertTrue(first === same)
        XCTAssertFalse(first === otherPart)
        XCTAssertFalse(first === otherLogin)
        weak var released: PlaybackWatchProgressSender?
        do {
            let unused = PlaybackWatchProgressSender.shared(loginSessionID: login, bvid: "unused", cid: 1) { _ in }
            released = unused
        }
        XCTAssertNil(released)
    }
}

private actor WatchReportRecorder {
    private(set) var values: [Double] = []
    func append(_ value: Double) { values.append(value) }
}

private actor WatchReportGate {
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
