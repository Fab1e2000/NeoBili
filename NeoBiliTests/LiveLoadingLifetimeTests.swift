import XCTest
@testable import NeoBili

@MainActor
final class LiveLoadingLifetimeTests: XCTestCase {
    func testPageRequesterCancellationDoesNotCancelPendingQualityLoad() async throws {
        let gate = LiveLifetimeGate()
        defer { Task { await gate.cancelAll() } }
        let model = makeModel(gate: gate)
        defer { model.stop() }
        // A page starts the operation, then its own task disappears during dismissal.
        let page = Task {
            model.requestLoad(quality: 250)
            try? await Task.sleep(for: .seconds(60))
        }
        try await waitUntil { await gate.hasPending(1) }
        page.cancel()
        await page.value
        model.pause()
        await gate.resolve(1, quality: 250)
        try await waitUntil { model.hasRenderedFirstFrame }
        XCTAssertEqual(model.selectedQuality, 250)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.isPlaying, "A pending first frame must retain the user's pause intent")
        XCTAssertNotNil(model.session.onEvent)
    }

    func testExplicitCloseRejectsLateOwnedLoadAndCancelsLoader() async throws {
        let gate = LiveLifetimeGate()
        defer { Task { await gate.cancelAll() } }
        var opens = 0
        let model = makeModel(gate: gate, opener: { _, _, _ in opens += 1 })
        model.requestLoad()
        try await waitUntil { await gate.hasPending(1) }
        model.stop()
        await gate.resolve(1, quality: 10000)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(opens, 0)
        XCTAssertFalse(model.hasRenderedFirstFrame)
        XCTAssertFalse(model.isPlaying)
        XCTAssertNil(model.session.onEvent)
        model.requestLoad()
        for _ in 0..<5 { await Task.yield() }
        let count = await gate.requests
        XCTAssertEqual(count, 1, "Closing the session is terminal")
    }

    func testNewQualityLoadRejectsSupersededResponse() async throws {
        let gate = LiveLifetimeGate()
        defer { Task { await gate.cancelAll() } }
        let model = makeModel(gate: gate)
        defer { model.stop() }
        model.requestLoad(quality: 400)
        try await waitUntil { await gate.hasPending(1) }
        model.requestLoad(quality: 250)
        try await waitUntil { await gate.hasPending(2) }
        await gate.resolve(2, quality: 250)
        try await waitUntil { model.hasRenderedFirstFrame }
        let active = model.session
        await gate.resolve(1, quality: 400)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(model.session === active)
        XCTAssertEqual(model.selectedQuality, 250)
        XCTAssertTrue(model.isPlaying)
    }

    private func makeModel(gate: LiveLifetimeGate,
                           opener: @escaping PlaybackSourceOpener = { session, _, _ in session.onEvent?(.firstFrame) }) -> LivePlayerModel {
        let room = LiveRoom(roomID: 17, title: "Fixture", username: "Fixture", liveStatus: 1)
        return LivePlayerModel(room: room, roomLoader: { _ in room },
                               playbackLoader: { _, _ in try await gate.load() },
                               sourceOpener: opener, publishesSystemMedia: false)
    }

    private func waitUntil(_ predicate: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Injected live session state did not complete")
        throw URLError(.timedOut)
    }
}

private actor LiveLifetimeGate {
    var requests = 0
    var pending: [Int: CheckedContinuation<LivePlayback, any Error>] = [:]
    func load() async throws -> LivePlayback {
        requests += 1
        let request = requests
        return try await withCheckedThrowingContinuation { pending[request] = $0 }
    }
    func hasPending(_ request: Int) -> Bool { pending[request] != nil }
    func resolve(_ request: Int, quality: Int) {
        let candidate = LiveStreamCandidate(url: URL(string: "https://stream.example.invalid/\(quality).m3u8")!,
                                            protocolName: "http_hls", formatName: "ts", codecName: "avc", quality: quality)
        pending.removeValue(forKey: request)?.resume(returning:
            LivePlayback(roomID: 17, liveStatus: 1, isPortrait: false,
                         qualities: [.init(id: quality, name: "Fixture")], candidates: [candidate]))
    }
    func cancelAll() {
        let remaining = Array(pending.values)
        pending.removeAll()
        for continuation in remaining { continuation.resume(throwing: CancellationError()) }
    }
}
