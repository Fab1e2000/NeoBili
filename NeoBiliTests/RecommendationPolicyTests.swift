import XCTest
@testable import NeoBili

final class RecommendationPolicyTests: XCTestCase {
    func testLifecycleConsumesColdAndHotOnlyOnceAndKeepsBannerInSession() {
        let session = AppRecommendationSession()
        let account = UUID()
        session.didBecomeActive() // Initial foreground is not a background return.
        let cold = session.takeRequest(accountSession: account)
        XCTAssertEqual(cold.openEvent, "cold")
        XCTAssertEqual(cold.bannerHash, "")
        session.recordBanner("own-response-hash", context: cold)
        XCTAssertEqual(session.takeRequest(accountSession: account).openEvent, "")
        session.didEnterBackground()
        session.didBecomeActive()
        let hot = session.takeRequest(accountSession: account)
        XCTAssertEqual(hot.openEvent, "hot")
        XCTAssertEqual(hot.bannerHash, "own-response-hash")
        session.recordBanner("another-hash", context: hot)
        XCTAssertEqual(session.takeRequest(accountSession: account).bannerHash, "own-response-hash")
        let newAccount = UUID()
        let switched = session.takeRequest(accountSession: newAccount)
        session.recordBanner("late-old-account", context: hot)
        XCTAssertEqual(switched.bannerHash, "")
        XCTAssertEqual(session.takeRequest(accountSession: newAccount).bannerHash, "", "Late old-account response must be ignored")
        XCTAssertEqual(AppRecommendationSession().takeRequest(accountSession: account).openEvent, "cold")
    }
    func testBannerIsReadBeforeUnsupportedCardFiltering() throws {
        let body = #"{"items":[{"card_goto":"banner","hash":"own-banner","banner_item":[],"idx":12},{"card_goto":"ad_av","hash":"unrelated","idx":13}]}"#
        let page = try JSONDecoder().decode(AppRecommendationPage.self, from: Data(body.utf8))
        XCTAssertEqual(page.bannerHash, "own-banner")
        XCTAssertEqual(page.nextCursor, 13)
        XCTAssertTrue(page.videos.isEmpty)
    }
    func testPoliciesApplyToInitialRefreshAndPaginationWithoutBorrowedState() {
        let fixed = ["auto_refresh_state":"4", "login_event":"0", "inline_sound":"1", "inline_sound_cold_state":"4",
                     "autoplay_card":"4", "video_mode":"1", "inline_danmu":"2", "client_attr":"1", "qn_policy":"1",
                     "player_net":"1", "guidance":"1", "soft_fnval":"2", "teenagers_age":"16", "fnval":"84948",
                     "fnver":"0", "force_host":"0", "https_url_req":"0", "qn":"32", "voice_balance":"0",
                     "disable_rcmd":"0", "recsys_mode":"0", "fourk":"1", "column":"4"]
        for request in [RecommendationRequest(source: .app), .init(source: .app, isRefresh: true), .init(source: .app, pageIndex: 2, appCursor: 123)] {
            let params = AppRecommendationPage.parameters(for: request, openEvent: "hot", bannerHash: "own-banner")
            for (key, value) in fixed { XCTAssertEqual(params[key], value, key) }
            XCTAssertEqual(params["open_event"], "hot")
            XCTAssertEqual(params["banner_hash"], "own-banner")
            for key in ["splash_id", "splash_ids", "splash_creative_id"] { XCTAssertEqual(params[key], "") }
            for key in ["ad_extra", "widgets", "network", "access_key"] { XCTAssertNil(params[key]) }
        }
        XCTAssertEqual(AppRecommendationPage.parameters(for: .init(source: .app, isLayoutChange: true))["flush"], "2")
        XCTAssertEqual(PlaybackEntry.history.parameters()["from"], "64")
        XCTAssertEqual(PlaybackEntry.search.parameters()["from"], "3")
    }
    func testChinaLocaleContainsOnlyKnownFields() throws {
        let data = try XCTUnwrap(Data(base64Encoded: AppRecommendationLocale.header))
        let locale = Data([10,2]) + Data("zh".utf8) + Data([18,4]) + Data("Hans".utf8) + Data([26,2]) + Data("CN".utf8)
        let expected = Data([10,14]) + locale + Data([18,14]) + locale + Data([34,13]) + Data("Asia/Shanghai".utf8)
        XCTAssertEqual(data, expected)
        XCTAssertFalse(data.contains(Data("USA".utf8)))
    }
}
