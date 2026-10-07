import Observation
import Synchronization
import XCTest
@testable import NeoBili

@MainActor
final class HomeInlinePreviewPerformanceTests: XCTestCase {
    private func video(_ id: Int, cid: Int? = nil) -> VideoSummary {
        var video = VideoSummary(bvid: "preview-performance-\(id)", aid: id, cid: cid ?? id,
            title: "Preview fixture", pic: "", desc: "", duration: 120, pubdate: 0,
            owner: .init(mid: 0, name: "Fixture", face: ""),
            stat: .init(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0))
        video.isLargeRecommendationCard = true
        return video
    }

    nonisolated private static func source() -> PlaybackSource {
        .init(video: .init(primary: URL(string: "https://example.invalid/preview")!, backups: []),
              audio: nil, duration: 120)
    }

    func testRapidlyPassingCardsAllocatesNoSessions() async throws {
        let loads = Mutex(0)
        var creations = 0
        var opens = 0
        let preview = HomeInlinePreview(loader: { _, _, _ in
            loads.withLock { $0 += 1 }
            return (1, Self.source())
        }, opener: { _, _ in opens += 1 }, sessionFactory: {
            creations += 1
            return MPVPlayerSession(configuration: $0)
        })
        // Each selection gets a run-loop opportunity to mount a surface. The
        // previous implementation exposed a new session on all twenty passes.
        for id in 1...20 {
            preview.select(video(id))
            XCTAssertNil(preview.session)
            try await Task.sleep(for: .milliseconds(5))
            preview.stop()
        }
        try await Task.sleep(for: .milliseconds(275))
        XCTAssertEqual(creations, 0)
        XCTAssertEqual(opens, 0)
        XCTAssertEqual(loads.withLock { $0 }, 0)
    }

    func testPendingAndCancelledLateManifestNeverAllocatesSession() async throws {
        let entered = expectation(description: "manifest load entered")
        let gate = InlinePreviewManifestGate()
        let reports = Mutex(0)
        var creations = 0
        var opens = 0
        let preview = HomeInlinePreview(loader: { _, _, _ in
            await gate.wait(entered: entered)
            return (1, Self.source())
        }, reporter: { _ in reports.withLock { $0 += 1 } },
           opener: { _, _ in opens += 1 }, sessionFactory: {
            creations += 1
            return MPVPlayerSession(configuration: $0)
        })
        preview.select(video(1))
        await fulfillment(of: [entered], timeout: 2)
        XCTAssertNil(preview.session)
        XCTAssertEqual(creations, 0)
        preview.stop()
        await gate.release()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNil(preview.session)
        XCTAssertNil(preview.videoID)
        XCTAssertEqual(creations, 0)
        XCTAssertEqual(opens, 0)
        XCTAssertEqual(reports.withLock { $0 }, 0)
    }

    func testSettledCardAllocatesOneSilentSessionAndRepeatedSelectionReusesIt() async throws {
        let opened = expectation(description: "settled preview opened")
        var configurations: [VideoPlaybackConfiguration] = []
        var opens = 0
        let preview = HomeInlinePreview(loader: { _, _, _ in (1, Self.source()) },
            opener: { _, _ in opens += 1; opened.fulfill() }, sessionFactory: {
                configurations.append($0)
                return MPVPlayerSession(configuration: $0)
            })
        defer { preview.stop() }
        let card = video(1)
        preview.select(card)
        XCTAssertNil(preview.session)
        await fulfillment(of: [opened], timeout: 2)
        let session = try XCTUnwrap(preview.session)
        for _ in 0..<100 { preview.select(card) }
        XCTAssertTrue(preview.session === session)
        XCTAssertEqual(opens, 1)
        XCTAssertEqual(configurations.count, 1)
        XCTAssertEqual(configurations.first?.quality, 32)
        XCTAssertEqual(configurations.first?.silentPreview, true)
        XCTAssertEqual(configurations.first?.maxBufferBytes, 8 * 1024 * 1024)
        XCTAssertEqual(configurations.first?.maxBackBufferBytes, 0)
    }

    func testStoppingCardWithoutCIDCancelsResolvedManifestFlight() async throws {
        let card = video(10, cid: 0)
        let started = expectation(description: "Resolved manifest started")
        let cancelled = expectation(description: "Underlying resolved manifest cancelled")
        let account = DeviceIdentity.shared.loginSessionID
        let cache = VideoPreparationCache(detailLoader: { bvid in
            VideoDetail(bvid: bvid, aid: 10, cid: 777, title: "Fixture", desc: "", pic: "",
                duration: 120, pubdate: 0, owner: .init(mid: 0, name: "Fixture", face: ""),
                stat: .init(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0),
                pages: [], tname: nil, copyright: nil, ugcSeason: nil)
        }, playbackLoader: { _, cid in
            XCTAssertEqual(cid, 777)
            return try await withTaskCancellationHandler {
                started.fulfill()
                try await Task.sleep(for: .seconds(60))
                throw URLError(.timedOut)
            } onCancel: { cancelled.fulfill() }
        }, sessionProvider: { account })
        let preview = HomeInlinePreview(loader: { video, owner, account in
            try await HomeInlinePreview.loadPreviewSource(video, owner: owner, account: account, cache: cache)
        })
        defer { preview.stop() }
        preview.select(card)
        await fulfillment(of: [started], timeout: 2)
        preview.stop()
        await fulfillment(of: [cancelled], timeout: 2)
        XCTAssertNil(preview.session)
    }

    func testRepeatedIdleStopsDoNotInvalidateObservedState() {
        let preview = HomeInlinePreview()
        let changes = Mutex(0)
        withObservationTracking {
            _ = preview.videoID
            _ = preview.session
            _ = preview.progress
            _ = preview.duration
            _ = preview.hasFirstFrame
        } onChange: {
            changes.withLock { $0 += 1 }
        }
        for _ in 0..<1_000 { preview.stop() }
        XCTAssertEqual(changes.withLock { $0 }, 0)
    }
}

private actor InlinePreviewManifestGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait(entered: XCTestExpectation) async {
        await withCheckedContinuation {
            continuation = $0
            entered.fulfill()
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
