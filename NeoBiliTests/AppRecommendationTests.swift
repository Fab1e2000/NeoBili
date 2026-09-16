import XCTest
@testable import NeoBili

final class AppRecommendationTests: XCTestCase {
    func testAppCardPreservesVideoIdentityAndPlaybackFields() throws {
        let page = try decode([card])
        let video = try XCTUnwrap(page.videos.first)
        XCTAssertEqual(video.aid, 170001)
        XCTAssertEqual(video.bvid, "BV17x411w7KC")
        XCTAssertEqual(video.cid, 279786)
        XCTAssertEqual(video.duration, 180)
        XCTAssertEqual(video.owner.mid, 42)
        XCTAssertEqual(video.owner.name, "测试 UP")
        XCTAssertEqual(video.stat.view, 125_000)
        XCTAssertEqual(video.stat.danmaku, 345)
        XCTAssertEqual(video.recommendationTrackID, "fixture-track")
    }

    func testAdsLiveAndMalformedCardsDoNotDiscardValidVideos() throws {
        var ad = card; ad["ad_info"] = ["id": 1]
        var live = card; live["goto"] = "live"
        var unplayable = card; unplayable["can_play"] = 0
        var malformed = card; malformed["player_args"] = "invalid"
        XCTAssertEqual(try decode([ad, live, unplayable, malformed, card]).videos.count, 1)
    }

    func testStringIDsAndProvidedBVIDAreSupported() throws {
        var value = card
        value["player_args"] = ["cid": "279786", "duration": "12"]
        value["bvid"] = "BV17x411w7KC"
        let video = try XCTUnwrap(decode([value]).videos.first)
        XCTAssertEqual(video.aid, 170001)
        XCTAssertEqual(video.cid, 279786)
        XCTAssertEqual(video.duration, 12)
    }

    func testAppParametersPreserveExistingCursor() {
        let params = AppRecommendationPage.parameters(freshIndex: 123)
        XCTAssertEqual(params["idx"], "123")
        XCTAssertEqual(params["mobi_app"], "android_i")
        XCTAssertNil(params["fresh_idx"])
        XCTAssertEqual(AppRecommendationPage.parameters(freshIndex: 0)["pull"], "true")
        XCTAssertEqual(AppRecommendationPage.count("1.2亿"), 120_000_000)
        XCTAssertNil(AppRecommendationPage.bvid(aid: -1))
    }

    /// 只读烟雾验证：直接访问 App 推荐，不允许热门兜底掩盖接口或解析错误。
    func testAppEndpointReturnsPlayableCardsOnDevice() async throws {
        let hasAppCredential = await DeviceIdentity.shared.accessKey?.isEmpty == false
        let videos = try await BiliAPI.recommendFeed(freshIndex: 0)
        print("AppRecommendationSmoke: cards=\(videos.count), appCredential=\(hasAppCredential)")
        XCTAssertFalse(videos.isEmpty)
        XCTAssertTrue(videos.allSatisfy { $0.aid > 0 && $0.cid > 0 && $0.bvid.hasPrefix("BV") })
    }

    private var card: [String: Any] {
        ["goto": "av", "card_goto": "av", "can_play": 1, "param": "170001",
         "title": "测试视频", "cover": "https://example.com/cover.jpg",
         "player_args": ["aid": 170001, "cid": 279786, "duration": 180],
         "args": ["up_id": 42, "up_name": "测试 UP"], "track_id": "fixture-track",
         "cover_left_text_1": "12.5万", "cover_left_text_2": "345"]
    }
    private func decode(_ items: [[String: Any]]) throws -> AppRecommendationPage {
        try JSONDecoder().decode(AppRecommendationPage.self, from: JSONSerialization.data(withJSONObject: ["items": items]))
    }
}
