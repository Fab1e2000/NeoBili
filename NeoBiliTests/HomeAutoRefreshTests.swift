import XCTest
@testable import NeoBili

@MainActor
final class HomeAutoRefreshTests: XCTestCase {
    private func config(_ json: String) throws -> AppRecommendationRefreshConfig {
        try JSONDecoder().decode(AppRecommendationRefreshConfig.self, from: Data(json.utf8))
    }

    private var video: VideoSummary {
        VideoSummary(bvid: "BVrefresh", aid: 1, cid: 1, title: "fixture", pic: "", desc: "", duration: 60,
                     pubdate: 0, owner: VideoOwner(mid: 1, name: "UP", face: ""),
                     stat: VideoStat(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0))
    }

    func testConfigUsesEventSecondsAndExplicitDisabledValuesOverrideLegacy() throws {
        let value = try config(#"{"auto_refresh_time":1200,"auto_refresh_time_by_active":"1800","auto_refresh_time_by_appear":0,"auto_refresh_time_by_behavior":-1}"#)
        XCTAssertEqual(value.active, 1800)
        XCTAssertNil(value.appear)
        XCTAssertNil(value.behavior)
        let legacy = try config(#"{"auto_refresh_time":1200}"#)
        XCTAssertEqual(legacy.appear, 1200)
        XCTAssertEqual(legacy.active, 1200)
        let malformed = try config(#"{"auto_refresh_time":1200,"auto_refresh_time_by_active":"oops","auto_refresh_time_by_appear":null}"#)
        XCTAssertNil(malformed.active)
        XCTAssertNil(malformed.appear)
        XCTAssertNil(try config("{}").behavior)
    }

    func testPagePreservesConfigAndIgnoresMalformedConfigWithoutLosingCursor() throws {
        for raw in [#"{"auto_refresh_time_by_active":1200}"#, "null", "[]", #""broken""#] {
            let page = try JSONDecoder().decode(AppRecommendationPage.self,
                from: Data("{\"items\":[{\"idx\":123}],\"config\":\(raw)}".utf8))
            XCTAssertEqual(page.nextCursor, 123)
            let batch = page.batch(for: RecommendationRequest(source: .app), filter: .none)
            XCTAssertEqual(batch.refreshConfig?.active, raw.hasPrefix("{") ? 1200 : nil)
        }
    }

    func testReturningNeverClaimsAutomaticRefreshEvenWithServerPolicy() async throws {
        var calls = 0
        let policy = try config(#"{"auto_refresh_time":1}"#)
        let model = HomeViewModel(defaults: UserDefaults(suiteName: UUID().uuidString)!, fetchRecommendations: { request in
            calls += 1
            return RecommendationBatch(videos: [self.video], nextRequest: request.next(appCursor: 42), refreshConfig: policy)
        })
        await model.loadInitial()
        for _ in 0..<5 {
            for trigger in [AppRecommendationRefreshConfig.Trigger.active, .appear, .behavior] {
                XCTAssertFalse(model.claimAutomaticRefresh(trigger))
            }
        }
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

}
