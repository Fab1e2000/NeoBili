import XCTest
@testable import NeoBili

@MainActor
final class PlayerLifecycleRepairTests: XCTestCase {
    func testSleepExpiryDuringRetryURLFetchSuppressesLateAutoplay() async throws {
        let payload = try JSONDecoder().decode(PlayURLData.self, from: Data("""
        {"quality":64,"durl":[{"order":1,"length":60000,"size":1,"url":"https://example.invalid/video.mp4"}]}
        """.utf8))
        let fetchingRetry = expectation(description: "Retry is waiting for its refreshed URL")
        let countdownStarted = expectation(description: "Sleep countdown started")
        let fetchGate = LifecycleRepairGate()
        let sleepGate = LifecycleRepairGate()
        let calls = LifecycleRepairURLLoader(payload: payload, gate: fetchGate, started: fetchingRetry)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "neobili.lifecycle-repair.\(UUID())"))
        let player = PlayerViewModel(bvid: "BVLifecycleRepair", cid: 11,
            playbackURLLoader: { _, _ in await calls.load() },
            watchProgressReporter: { _, _, _ in }, progressStore: PlaybackProgressStore(defaults: defaults),
            sleepWaiter: { _ in await sleepGate.wait(started: countdownStarted) },
            sourceOpener: { _, _, _ in })
        defer { player.stop() }
        await player.load()
        player.session.onEvent?(.firstFrame)
        player.session.onEvent?(.playing(true))
        player.session.onEvent?(.error("Expired URL"))
        XCTAssertNotNil(player.errorMessage)
        player.setSleepTimer(.minutes(15))
        await fulfillment(of: [countdownStarted], timeout: 2)
        let retry = Task { await player.retry() }
        await fulfillment(of: [fetchingRetry], timeout: 2)
        XCTAssertTrue(player.isLoading)
        XCTAssertFalse(player.isPlaying)
        await sleepGate.release()
        // Wait for the actual countdown task to apply the pause intent.
        for _ in 0..<200 {
            if !player.isSleepTimerActive { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(player.isSleepTimerActive)
        await fetchGate.release()
        await retry.value
        player.session.onEvent?(.playing(true))
        XCTAssertFalse(player.isPlaying, "Loading completion must not defeat an expired sleep timer")
        player.session.onEvent?(.firstFrame)
        XCTAssertFalse(player.isPlaying)
        player.play()
        XCTAssertTrue(player.isPlaying, "Explicit user resume should still work after sleeping")
    }

    func testStopCancelsWaitingDanmakuAndIgnoresLateResult() async throws {
        let loading = expectation(description: "Danmaku loader started")
        let cancelled = expectation(description: "Danmaku task cancelled")
        let finished = expectation(description: "Noncooperative loader returned after cancellation")
        let gate = LifecycleRepairGate()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "neobili.danmaku-stop.\(UUID())"))
        let player = PlayerViewModel(bvid: "BVDanmakuStop", cid: 12,
            playbackURLLoader: { _, _ in throw URLError(.notConnectedToInternet) },
            watchProgressReporter: { _, _, _ in }, progressStore: PlaybackProgressStore(defaults: defaults),
            danmakuLoader: { _ in
                await withTaskCancellationHandler {
                    await gate.wait(started: loading)
                    finished.fulfill()
                    return [DanmakuItem(time: 1, text: "late", mode: 1, color: 0xFFFFFF)]
                } onCancel: { cancelled.fulfill() }
            }, sourceOpener: { _, _, _ in })
        player.ensureDanmaku()
        let controller = try XCTUnwrap(player.danmaku)
        await fulfillment(of: [loading], timeout: 2)
        player.stop()
        await fulfillment(of: [cancelled], timeout: 2)
        XCTAssertNil(player.danmaku)
        await gate.release()
        await fulfillment(of: [finished], timeout: 2)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(controller.state, .idle, "A late result must not revive the closed controller")
        controller.load()
        XCTAssertEqual(controller.state, .idle)
    }

    func testCancelledDanmakuParseDoesNotProcessItems() async {
        let xml = Data("<i><d p=\"1,1,25,16777215,0,0,0,1\">item</d></i>".utf8)
        XCTAssertEqual(DanmakuLoader.parse(xml).count, 1)
        let started = expectation(description: "Parser task ready")
        let gate = LifecycleRepairGate()
        let parsing = Task {
            await gate.wait(started: started)
            return DanmakuLoader.parse(xml)
        }
        await fulfillment(of: [started], timeout: 2)
        parsing.cancel()
        await gate.release()
        let items = await parsing.value
        XCTAssertTrue(items.isEmpty)
    }

    func testDroppingControllerCancelsLoaderWithoutRetainingController() async {
        let loading = expectation(description: "Danmaku loader started")
        let cancelled = expectation(description: "Released controller cancels task")
        let gate = LifecycleRepairGate()
        var controller: DanmakuController? = DanmakuController(bvid: "BVDanmakuRelease", cid: 13, loader: { _ in
            await withTaskCancellationHandler {
                await gate.wait(started: loading)
                return []
            } onCancel: { cancelled.fulfill() }
        })
        weak var released = controller
        controller?.load()
        await fulfillment(of: [loading], timeout: 2)
        controller = nil
        XCTAssertNil(released, "The waiting load task must not retain its controller")
        await fulfillment(of: [cancelled], timeout: 2)
        await gate.release()
    }
}

private actor LifecycleRepairGate {
    private var continuation: CheckedContinuation<Void, Never>?
    func wait(started: XCTestExpectation) async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }
    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor LifecycleRepairURLLoader {
    let payload: PlayURLData
    let gate: LifecycleRepairGate
    let started: XCTestExpectation
    var calls = 0
    init(payload: PlayURLData, gate: LifecycleRepairGate, started: XCTestExpectation) {
        self.payload = payload
        self.gate = gate
        self.started = started
    }
    func load() async -> PlayURLData {
        calls += 1
        if calls > 1 { await gate.wait(started: started) }
        return payload
    }
}
