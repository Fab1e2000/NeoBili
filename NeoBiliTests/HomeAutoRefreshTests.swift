@testable import NeoBiliData
@testable import NeoBiliDomain
import XCTest
@testable import NeoBili

@MainActor
final class HomeAutoRefreshTests: XCTestCase {
    private var video: VideoSummary {
        VideoSummary(bvid: "BVrefresh", aid: 1, cid: 1, title: "fixture", pic: "", desc: "", duration: 60,
                     pubdate: 0, owner: VideoOwner(mid: 1, name: "UP", face: ""),
                     stat: VideoStat(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0))
    }

    func testPagingCursorSurvivesUnknownOrMalformedConfiguration() throws {
        for raw in [#"{"auto_refresh_time_by_active":1200}"#, "null", "[]", #""broken""#] {
            let page = try JSONDecoder().decode(AppRecommendationPage.self,
                from: Data("{\"items\":[{\"idx\":123}],\"config\":\(raw)}".utf8))
            XCTAssertEqual(page.nextCursor, 123)
            let batch = page.batch(for: RecommendationRequest(source: .app), filter: .none)
            XCTAssertEqual(batch.nextRequest?.appCursor, 123)
        }
    }

    /// 取消或离开页面后丢弃的暂存批次不能被迟到的提交换进列表。
    func testDiscardedStagedRefreshIsNeverCommitted() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let staged = VideoSummary(bvid: "BVstaged", aid: 2, cid: 2, title: "staged", pic: "", desc: "",
                                  duration: 60, pubdate: 0, owner: video.owner, stat: video.stat)
        var next = video
        let model = HomeViewModel(defaults: defaults, fetchRecommendations: { _ in
            RecommendationBatch(videos: [next], nextRequest: nil)
        })
        await model.loadInitial()
        XCTAssertEqual(model.videos.map(\.bvid), ["BVrefresh"])

        next = staged
        await model.refresh(staged: true, userInitiated: true)
        XCTAssertEqual(model.videos.map(\.bvid), ["BVrefresh"], "the staged batch stays hidden")

        model.discardStagedRefresh()
        model.commitStagedRefresh()
        XCTAssertEqual(model.videos.map(\.bvid), ["BVrefresh"], "a discarded batch never replaces the list")
    }

    #if NEOBILI_REGRESSION
    /// 列表与过滤输入不变时，页面求值复用已算好的行，不再全量重扫。
    func testFilteredRowsAreReusedUntilAnInputChanges() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let filtering = VideoFilterDependencies(
            duration: VideoDurationFilterSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            metadata: PortraitVideoStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                metadataLoader: { _ in throw URLError(.cannotConnectToHost) }))
        let model = HomeViewModel(defaults: defaults, filtering: filtering, fetchRecommendations: { _ in
            RecommendationBatch(videos: [self.video], nextRequest: nil)
        })
        await model.loadInitial()
        _ = model.feedRows(hidingKnownPortraitVideos: false)
        let first = model.feedRowsComputationCount
        _ = model.feedRows(hidingKnownPortraitVideos: false)
        XCTAssertEqual(model.feedRowsComputationCount, first, "unchanged inputs reuse the cached rows")
        _ = model.feedRows(hidingKnownPortraitVideos: true)
        XCTAssertEqual(model.feedRowsComputationCount, first + 1, "a filter change recomputes")
    }
    #endif

    func testReopeningHomeKeepsTheFeedUntilManualRefreshOrPagination() async {
        var calls = 0
        let model = HomeViewModel(defaults: UserDefaults(suiteName: UUID().uuidString)!, fetchRecommendations: { request in
            calls += 1
            return RecommendationBatch(videos: [self.video], nextRequest: request.next(appCursor: 42))
        })
        await model.loadInitial()
        await model.loadInitial()
        XCTAssertEqual(model.videos.map(\.bvid), ["BVrefresh"])
        XCTAssertEqual(calls, 1)
        await model.refresh(userInitiated: true)
        XCTAssertEqual(calls, 2, "Manual refresh remains available")
        await model.loadReplacementPage()
        XCTAssertEqual(calls, 3, "Pagination remains available")
    }

    func testBlockingManyCardsUpdatesRefreshBoundaryOnce() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let session = UUID()
        let owner = VideoOwner(mid: 1, name: "UP", face: "")
        func card(_ id: String, mid: Int) -> VideoSummary {
            VideoSummary(bvid: id, aid: 1, cid: 1, title: id, pic: "", desc: "", duration: 60,
                         pubdate: 0, owner: VideoOwner(mid: mid, name: "UP", face: ""),
                         stat: VideoStat(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0))
        }
        let model = HomeViewModel(defaults: defaults, blockUser: { _ in },
            currentAccount: { HomeFeedAccount(accountID: nil, hasAppCredential: false) },
            currentSessionID: { session }, fetchRecommendations: { request in
                RecommendationBatch(videos: request.isRefresh
                    ? [card("new-blocked", mid: 1), card("new-kept", mid: 2)]
                    : [card("old-blocked", mid: 1), card("old-kept", mid: 2)], nextRequest: nil)
            })
        await model.loadInitial()
        await model.refresh()
        XCTAssertEqual(model.lastRefreshAt, 2)
        _ = await model.block(owner)
        XCTAssertEqual(model.videos.map(\.bvid), ["new-kept", "old-kept"])
        XCTAssertEqual(model.lastRefreshAt, 1)
    }

    func testBlockResponseFromPreviousSessionDoesNotMutateCurrentFeed() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var session = UUID()
        let model = HomeViewModel(defaults: defaults, blockUser: { _ in session = UUID() },
            currentAccount: { HomeFeedAccount(accountID: nil, hasAppCredential: false) },
            currentSessionID: { session }, fetchRecommendations: { _ in
                RecommendationBatch(videos: [self.video], nextRequest: nil)
            })
        await model.loadInitial()
        let message = await model.block(video.owner)
        XCTAssertNil(message)
        XCTAssertEqual(model.videos.count, 1)
    }

    func testLateFailureIsPublishedOnlyForRequestAccountSession() async {
        for changesAccount in [false, true] {
            let suite = "neobili.home.late-failure.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            var session = UUID()
            let started = expectation(description: "Recommendation request suspended")
            var response: CheckedContinuation<RecommendationBatch, any Error>?
            let model = HomeViewModel(defaults: defaults,
                currentAccount: { HomeFeedAccount(accountID: nil, hasAppCredential: false) },
                currentSessionID: { session }, fetchRecommendations: { _ in
                    try await withCheckedThrowingContinuation {
                        response = $0
                        started.fulfill()
                    }
                })
            let load = Task { await model.loadInitial() }
            await fulfillment(of: [started], timeout: 2)
            if changesAccount { session = UUID() }
            let failure = URLError(.timedOut)
            response?.resume(throwing: failure)
            await load.value
            XCTAssertEqual(model.errorMessage, changesAccount ? nil : String(localized: "请求超时，请稍后重试。"))
            XCTAssertTrue(model.videos.isEmpty)
            XCTAssertFalse(model.isLoading)
        }
    }

}
