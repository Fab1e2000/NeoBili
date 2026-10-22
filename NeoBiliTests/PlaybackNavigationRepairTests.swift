#if canImport(NeoBiliDomain)
@testable import NeoBiliDomain
#endif
import XCTest
@testable import NeoBili

@MainActor
final class PlaybackNavigationRepairTests: XCTestCase {
    func testHistoryRestoresSelectedPartAcrossEpisodeAndCommentNavigation() throws {
        let store = try makeStore()
        defer { store.close() }
        store.open(VideoDetailRoute(bvid: "BVFirst", cid: 11), from: "card")
        store.selectPart(cid: 13)
        store.openEpisode(.init(episodeId: 2, aid: 2, cid: 21, bvid: "BVSecond", title: "Second", arc: nil))
        store.selectPart(cid: 23)
        store.isExpanded = true
        store.openCommentVideo(VideoDetailRoute(bvid: "BVThird", cid: 31))
        store.goBack()
        XCTAssertEqual(store.route?.bvid, "BVSecond")
        XCTAssertEqual(store.activeCid, 23)
        store.goBack()
        XCTAssertEqual(store.route?.bvid, "BVFirst")
        XCTAssertEqual(store.activeCid, 13)
    }

    func testHistoryRestoresSelectedPartForEntryWithoutCidAndRelatedNavigation() throws {
        let store = try makeStore()
        defer { store.close() }
        store.open(VideoDetailRoute(bvid: "BVWithoutCid"), from: "search")
        store.selectPart(cid: 103)
        store.openRelated(VideoSummary(bvid: "BVRelated", aid: 2, cid: 201, title: "Related", pic: "", desc: "",
                                      duration: 1, pubdate: 0, owner: .init(mid: 0, name: "", face: ""),
                                      stat: .init(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0)))
        store.goBack()
        XCTAssertEqual(store.route?.bvid, "BVWithoutCid")
        XCTAssertEqual(store.activeCid, 103)
    }

    func testSameVideoReopenKeepsSelectedPart() throws {
        let store = try makeStore()
        defer { store.close() }
        store.open(VideoDetailRoute(bvid: "BVSame", cid: 1), from: "card")
        store.selectPart(cid: 3)
        store.open(VideoDetailRoute(bvid: "BVSame", cid: 2), from: "history")
        XCTAssertEqual(store.activeCid, 3, "This repair must preserve existing same-video reopening semantics")
    }

    func testDetailRetryBuildsPlayerAndCommentsWithoutReplacingTheSessionModel() async throws {
        let gate = NavigationDetailGate()
        let store = try makeStore(loader: { _ in try await gate.load() })
        defer { store.close(); gate.cancelAll() }
        store.open(VideoDetailRoute(bvid: "BVRetry"), from: "search")
        store.requestPlayback()
        let model = try XCTUnwrap(store.detailViewModel)
        try await waitUntil { gate.pending[1] != nil }
        gate.fail(1)
        try await waitUntil { model.errorMessage != nil && !model.isLoading }
        // The failed detail belongs to the persistent session; reopening keeps it available to retry.
        store.open(VideoDetailRoute(bvid: "BVRetry"), from: "search")
        XCTAssertTrue(store.detailViewModel === model)
        store.retryDetail()
        store.retryDetail()
        try await waitUntil { gate.pending[2] != nil }
        XCTAssertEqual(gate.requests, 2, "Consecutive retry taps must share one request")
        gate.resolve(2, value: detail(bvid: "BVRetry", aid: 77, cid: 777))
        try await waitUntil { store.commentsViewModel != nil && store.player != nil }
        XCTAssertTrue(store.detailViewModel === model)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(store.player?.cid, 777)
        XCTAssertEqual(store.commentsViewModel?.oid, 77)
    }

    func testLateCancelledDetailCannotBuildStateForAnotherVideo() async throws {
        let gate = NavigationDetailGate()
        let store = try makeStore(loader: { _ in try await gate.load() })
        defer { store.close(); gate.cancelAll() }
        store.open(VideoDetailRoute(bvid: "BVOld"), from: "card")
        try await waitUntil { gate.pending[1] != nil }
        store.open(VideoDetailRoute(bvid: "BVNew"), from: "card")
        try await waitUntil { gate.pending[2] != nil }
        gate.resolve(2, value: detail(bvid: "BVNew", aid: 2, cid: 22))
        try await waitUntil { store.commentsViewModel?.oid == 2 }
        gate.resolve(1, value: detail(bvid: "BVOld", aid: 1, cid: 11))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(store.route?.bvid, "BVNew")
        XCTAssertEqual(store.detailViewModel?.detail?.cid, 22)
        XCTAssertEqual(store.commentsViewModel?.oid, 2)
        XCTAssertNil(store.player)
    }

    func testLateDetailPreservesLatestSelectedPartOfSameVideo() async throws {
        let gate = NavigationDetailGate()
        let store = try makeStore(loader: { _ in try await gate.load() })
        defer { store.close(); gate.cancelAll() }
        store.open(VideoDetailRoute(bvid: "BVParts"), from: "search")
        try await waitUntil { gate.pending[1] != nil }
        store.selectPart(cid: 11)
        store.selectPart(cid: 12)
        store.selectPart(cid: 13)
        gate.resolve(1, value: detail(bvid: "BVParts", aid: 7, cid: 11))
        try await waitUntil { store.commentsViewModel?.oid == 7 }
        XCTAssertEqual(store.activeCid, 13)
        XCTAssertNil(store.player)
        store.requestPlayback()
        XCTAssertEqual(store.player?.cid, 13)
    }

    func testClosedNavigationReleasesModelsAfterCancelledWorkFinishes() async throws {
        var store: NowPlayingStore? = try makeStore()
        weak var releasedStore = store
        store?.open(VideoDetailRoute(bvid: "BVFirst"), from: "card")
        weak var first = store?.detailViewModel
        store?.openEpisode(.init(episodeId: 2, aid: 2, cid: 21, bvid: "BVSecond", title: "Second", arc: nil))
        weak var second = store?.detailViewModel
        store?.isExpanded = true
        store?.openCommentVideo(VideoDetailRoute(bvid: "BVThird"))
        weak var third = store?.detailViewModel
        store?.goBack()
        weak var restored = store?.detailViewModel
        XCTAssertEqual(store?.route?.bvid, "BVSecond")
        store?.close()
        store = nil
        try await waitUntil {
            releasedStore == nil && first == nil && second == nil && third == nil && restored == nil
        }
    }

    func testClosedDetailReleasesAfterPendingRequestCompletes() async throws {
        for completesSuccessfully in [false, true] {
            let gate = NavigationDetailGate()
            defer { gate.cancelAll() }
            var store: NowPlayingStore? = try makeStore(loader: { _ in try await gate.load() })
            weak var releasedStore = store
            store?.open(VideoDetailRoute(bvid: "BVPending"), from: "card")
            weak var releasedDetail = store?.detailViewModel
            try await waitUntil { gate.pending[1] != nil }
            store?.close()
            store = nil
            if completesSuccessfully {
                gate.resolve(1, value: detail(bvid: "BVPending", aid: 1, cid: 11))
            } else {
                gate.cancelAll()
            }
            try await waitUntil { releasedStore == nil && releasedDetail == nil }
        }
    }

    private func makeStore(loader: @escaping @MainActor (String) async throws -> VideoDetail = { _ in
        throw URLError(.notConnectedToInternet)
    }) throws -> NowPlayingStore {
        let suite = "neobili.navigation-repair.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: DetailPlaybackSettings.storageKey)
        let dependencies = PlaybackDependencies.isolated(defaults: defaults)
        return NowPlayingStore(defaults: defaults, detailModelFactory: {
            VideoDetailViewModel(bvid: $0.bvid, likeStore: dependencies.likes,
                                 services: dependencies.services, fetchDetail: loader)
        }, dependencies: dependencies)
    }

    private func detail(bvid: String, aid: Int, cid: Int) -> VideoDetail {
        VideoDetail(bvid: bvid, aid: aid, cid: cid, title: "Fixture", desc: "", pic: "", duration: 1, pubdate: 0,
                    owner: .init(mid: 0, name: "", face: ""),
                    stat: .init(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0),
                    pages: [], tname: nil, copyright: nil, ugcSeason: nil)
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Injected detail state did not complete")
        throw URLError(.timedOut)
    }
}

@MainActor
private final class NavigationDetailGate {
    var requests = 0
    var pending: [Int: CheckedContinuation<VideoDetail, any Error>] = [:]
    func load() async throws -> VideoDetail {
        requests += 1
        let request = requests
        return try await withCheckedThrowingContinuation { pending[request] = $0 }
    }
    func fail(_ request: Int) { pending.removeValue(forKey: request)?.resume(throwing: URLError(.notConnectedToInternet)) }
    func resolve(_ request: Int, value: VideoDetail) { pending.removeValue(forKey: request)?.resume(returning: value) }
    func cancelAll() {
        let remaining = Array(pending.values)
        pending.removeAll()
        for continuation in remaining { continuation.resume(throwing: CancellationError()) }
    }
}
