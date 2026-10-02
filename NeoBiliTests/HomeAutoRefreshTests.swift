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

    func testDeadlineUsesLastRefreshNotPaginationAndEventsCoalesce() async throws {
        var now: TimeInterval = 100
        let policy = try config(#"{"auto_refresh_time_by_active":1200,"auto_refresh_time_by_appear":1800,"auto_refresh_time_by_behavior":1800}"#)
        let model = HomeViewModel(defaults: UserDefaults(suiteName: UUID().uuidString)!, uptime: { now }, fetchRecommendations: { request in
            RecommendationBatch(videos: [self.video], nextRequest: request.next(appCursor: 42), refreshConfig: policy)
        })
        XCTAssertFalse(model.claimAutomaticRefresh(.active))
        await model.loadInitial()
        now = 1200
        await model.loadReplacementPage()
        now = 1299
        XCTAssertFalse(model.claimAutomaticRefresh(.active))
        now = 1300
        XCTAssertFalse(model.claimAutomaticRefresh(.appear))
        XCTAssertTrue(model.claimAutomaticRefresh(.active))
        XCTAssertFalse(model.claimAutomaticRefresh(.active))
        await model.refresh()
        now = 2499
        XCTAssertFalse(model.claimAutomaticRefresh(.active))
        now = 3100
        XCTAssertTrue(model.claimAutomaticRefresh(.behavior))
        XCTAssertFalse(model.claimAutomaticRefresh(.appear))
    }

    func testFailedAutomaticRefreshKeepsContentAndRateLimitsRetry() async throws {
        var now: TimeInterval = 0
        var calls = 0
        let policy = try config(#"{"auto_refresh_time":10}"#)
        let model = HomeViewModel(defaults: UserDefaults(suiteName: UUID().uuidString)!, uptime: { now }, fetchRecommendations: { request in
            calls += 1
            if calls > 1 { throw URLError(.timedOut) }
            return RecommendationBatch(videos: [self.video], nextRequest: request.next(appCursor: 42), refreshConfig: policy)
        })
        await model.loadInitial()
        now = 10
        XCTAssertTrue(model.claimAutomaticRefresh(.appear))
        await model.refresh()
        XCTAssertEqual(model.videos.count, 1)
        XCTAssertNotNil(model.errorMessage)
        now = 69
        XCTAssertFalse(model.claimAutomaticRefresh(.active))
        now = 70
        XCTAssertTrue(model.claimAutomaticRefresh(.active))
    }

    func testStagedRefreshWebSourceAndMissingConfigPreventAutomaticRefresh() async throws {
        var now: TimeInterval = 0
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var policy: AppRecommendationRefreshConfig? = try config(#"{"auto_refresh_time":10}"#)
        let model = HomeViewModel(defaults: defaults, uptime: { now }, fetchRecommendations: { request in
            RecommendationBatch(videos: [self.video], nextRequest: request.next(appCursor: 42), refreshConfig: policy)
        })
        await model.loadInitial()
        await model.refresh(staged: true)
        now = 100
        XCTAssertFalse(model.claimAutomaticRefresh(.appear))
        model.commitStagedRefresh()
        defaults.set(false, forKey: RecommendationFilter.appRecommendKey)
        XCTAssertFalse(model.claimAutomaticRefresh(.appear))
        await model.refresh()
        defaults.set(true, forKey: RecommendationFilter.appRecommendKey)
        policy = nil
        await model.refresh()
        now = 10000
        XCTAssertFalse(model.claimAutomaticRefresh(.active))
    }

    func testLateCanceledResponseCannotReplaceNewRefreshConfiguration() async throws {
        var now: TimeInterval = 0
        var calls = 0
        var pending: CheckedContinuation<RecommendationBatch, Never>?
        let suspended = expectation(description: "Old request suspended")
        let enabled = try config(#"{"auto_refresh_time":10}"#)
        let disabled = try config(#"{"auto_refresh_time":0}"#)
        let model = HomeViewModel(defaults: UserDefaults(suiteName: UUID().uuidString)!, uptime: { now }, fetchRecommendations: { request in
            calls += 1
            if calls == 2 {
                return await withCheckedContinuation { pending = $0; suspended.fulfill() }
            }
            return RecommendationBatch(videos: [self.video], nextRequest: request.next(appCursor: 42),
                                       refreshConfig: calls == 1 ? enabled : disabled)
        })
        await model.loadInitial()
        let old = Task { await model.loadReplacementPage() }
        await fulfillment(of: [suspended], timeout: 2)
        now = 100
        XCTAssertFalse(model.claimAutomaticRefresh(.active), "Loading cannot trigger automatic refresh")
        await model.refresh()
        pending?.resume(returning: RecommendationBatch(videos: [video], nextRequest: nil, refreshConfig: enabled))
        await old.value
        now = 1000
        XCTAssertFalse(model.claimAutomaticRefresh(.active))
    }
}
