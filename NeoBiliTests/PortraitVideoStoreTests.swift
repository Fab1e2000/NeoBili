import XCTest
import Observation
@testable import NeoBili

@MainActor
final class PortraitVideoStoreTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "PortraitVideoStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testResultsSurviveNewStoreAndExpire() async {
        let defaults = defaults()
        var now = Date(timeIntervalSince1970: 1_000)
        var calls = 0
        let store = PortraitVideoStore(defaults: defaults, now: { now }) { _ in
            calls += 1
            return VideoDimension(width: 720, height: 1280)
        }
        await store.resolve(["BVportrait", "BVportrait"])
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(store.isPortrait(bvid: "BVportrait"), true)

        let restored = PortraitVideoStore(defaults: defaults, now: { now }) { _ in
            calls += 1
            return VideoDimension(width: 1920, height: 1080)
        }
        await restored.resolve(["BVportrait"])
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(restored.isPortrait(bvid: "BVportrait"), true)
        now.addTimeInterval(7 * 86_400 + 1)
        XCTAssertNil(restored.isPortrait(bvid: "BVportrait"))
        await restored.resolve(["BVportrait"])
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(restored.isPortrait(bvid: "BVportrait"), false)
    }

    func testFailuresAndInvalidDimensionsRemainUnknownAndRetryAfterCooldown() async {
        var now = Date(timeIntervalSince1970: 1_000)
        var calls = 0
        let store = PortraitVideoStore(defaults: defaults(), now: { now }) { _ in
            calls += 1
            if calls == 1 { throw URLError(.notConnectedToInternet) }
            if calls == 2 { return VideoDimension(width: 0, height: 1280) }
            return VideoDimension(width: 720, height: 1280)
        }
        await store.resolve(["BVretry"])
        XCTAssertNil(store.isPortrait(bvid: "BVretry"))
        await store.resolve(["BVretry"])
        XCTAssertEqual(calls, 1)
        now.addTimeInterval(301)
        await store.resolve(["BVretry"])
        XCTAssertNil(store.isPortrait(bvid: "BVretry"))
        now.addTimeInterval(301)
        await store.resolve(["BVretry"])
        XCTAssertEqual(store.isPortrait(bvid: "BVretry"), true)
        XCTAssertEqual(calls, 3)
    }

    func testSquareLandscapeAndRotatedDimensionsAreCached() async {
        var calls = 0
        let store = PortraitVideoStore(defaults: defaults()) { bvid in
            calls += 1
            switch bvid {
            case "square": return VideoDimension(width: 720, height: 720)
            case "rotated": return VideoDimension(width: 1920, height: 1080, rotate: 90)
            default: return VideoDimension(width: 1920, height: 1080)
            }
        }
        await store.resolve(["square", "landscape", "rotated", ""])
        await store.resolve(["square", "landscape", "rotated"])
        XCTAssertEqual(calls, 3)
        XCTAssertEqual(store.isPortrait(bvid: "square"), false)
        XCTAssertEqual(store.isPortrait(bvid: "landscape"), false)
        XCTAssertEqual(store.isPortrait(bvid: "rotated"), true)
    }

    func testConcurrentListsShareRequestsAndLimitConcurrency() async {
        let probe = Probe()
        let store = PortraitVideoStore(defaults: defaults()) { await probe.load($0) }
        let first = Task { await store.resolve(["A"]) }
        let duplicate = Task { await store.resolve(["A"]) }
        let second = Task { await store.resolve(["B"]) }
        let third = Task { await store.resolve(["C"]) }
        await waitUntil { probe.pending.count == 2 }
        XCTAssertEqual(probe.started.count, 2)
        probe.finishOne()
        await waitUntil { probe.started.count == 3 }
        XCTAssertEqual(probe.pending.count, 2)
        probe.finishOne()
        probe.finishOne()
        await first.value
        await duplicate.value
        await second.value
        await third.value
        XCTAssertEqual(probe.started.filter { $0 == "A" }.count, 1)
        XCTAssertEqual(Set(probe.started), Set(["A", "B", "C"]))
    }

    func testCancellingListStopsRemainingLookupsButKeepsSharedResult() async {
        let probe = Probe()
        let store = PortraitVideoStore(defaults: defaults()) { await probe.load($0) }
        let task = Task { await store.resolve(["A", "B"]) }
        await waitUntil { probe.pending.count == 1 }
        task.cancel()
        probe.finishOne()
        await task.value
        XCTAssertEqual(probe.started, ["A"])
        XCTAssertEqual(store.isPortrait(bvid: "A"), true)
        XCTAssertNil(store.isPortrait(bvid: "B"))
    }

    func testResolutionPublishesObservationChangeForVisibleLists() async {
        let store = PortraitVideoStore(defaults: defaults()) { _ in
            VideoDimension(width: 720, height: 1280)
        }
        let changed = expectation(description: "List observes classification")
        withObservationTracking {
            XCTAssertNil(store.isPortrait(bvid: "A"))
        } onChange: {
            changed.fulfill()
        }
        await store.resolve(["A"])
        await fulfillment(of: [changed], timeout: 1)
        XCTAssertEqual(store.isPortrait(bvid: "A"), true)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Timed out waiting for lookup")
    }

    @MainActor
    private final class Probe {
        var started: [String] = []
        var pending: [CheckedContinuation<VideoDimension?, Never>] = []

        func load(_ bvid: String) async -> VideoDimension? {
            started.append(bvid)
            return await withCheckedContinuation { pending.append($0) }
        }

        func finishOne() {
            guard !pending.isEmpty else { return }
            pending.removeFirst().resume(returning: VideoDimension(width: 720, height: 1280))
        }
    }
}
