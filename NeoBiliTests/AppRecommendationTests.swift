import XCTest
@testable import NeoBili

final class AppRecommendationTests: XCTestCase {
    func testCardRetainsOnlyItsOwnServerTrackingFields() throws {
        var tracked = card
        tracked["track_id"] = "fixture-track"
        tracked["report_flow_data"] = "fixture-flow"
        let video = try XCTUnwrap(decode([tracked]).videos.first)
        XCTAssertEqual(video.playbackEntry.source, .recommendation)
        XCTAssertEqual(video.playbackEntry.parameters()["track_id"], "fixture-track")
        XCTAssertEqual(video.playbackEntry.parameters()["report_flow_data"], "fixture-flow")
        XCTAssertNil(try decode([card]).videos.first?.playbackEntry.parameters()["track_id"])
    }

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
        XCTAssertEqual(video.recommendationFeedback?.goto, "av")
        XCTAssertEqual(video.recommendationFeedback?.param, 170001)
        XCTAssertEqual(video.recommendationFeedback?.dislikeReasons?.first?.id, 1)
        XCTAssertEqual(video.recommendationFeedback?.feedbacks?.first?.toast, "感谢反馈")
    }

    func testAdsAndMalformedCardsDoNotDiscardValidVideos() throws {
        var ad = card; ad["ad_info"] = ["id": 1]
        var bangumi = card; bangumi["card_goto"] = "bangumi"
        var promoted = card; promoted["card_goto"] = "ad_web_s"
        var inlineAd = card; inlineAd["card_goto"] = "ad_inline_av"
        var noArgs = card; noArgs["args"] = nil
        var unplayable = card; unplayable["can_play"] = 0
        var malformed = card; malformed["player_args"] = "invalid"
        let videos = try decode([ad, bangumi, promoted, inlineAd, noArgs, unplayable, malformed, card]).videos
        XCTAssertEqual(videos.count, 1)
        XCTAssertEqual(videos.map(\.aid), [170001])
        XCTAssertEqual(videos.map(\.cid), [279786],
                       "Malformed player_args must be filtered; missing or null arguments are tested separately")
    }

    func testMissingOrNullPlaybackArgumentsPreserveResolvableVideoIdentity() throws {
        var missing = card; missing["player_args"] = nil
        var null = card; null["player_args"] = NSNull()
        let videos = try decode([missing, null]).videos
        XCTAssertEqual(videos.map(\.bvid), ["BV17x411w7KC", "BV17x411w7KC"])
        XCTAssertEqual(videos.map(\.cid), [0, 0], "缺少分 P 身份时仍可在详情页补查")
    }

    @MainActor
    func testInlineLiveAndPictureCardsAreShown() throws {
        var inline = card; inline["card_goto"] = "inline_av_v2"
        let live: [String: Any] = ["card_goto": "live", "param": "7736134", "title": "直播标题",
                                   "cover": "https://example.com/l.jpg", "cover_left_text_1": "1015",
                                   "args": ["room_id": 7736134, "up_id": 28027385, "up_name": "主播", "tname": "其他单机", "online": 1156]]
        let picture: [String: Any] = ["card_goto": "picture", "param": "1", "title": "图文",
                                      "cover": "https://example.com/p.jpg", "uri": "bilibili://following/detail/987654321",
                                      "args": ["up_id": 5], "desc_button": ["text": "作者"]]
        let videos = try decode([inline, live, picture]).videos
        XCTAssertEqual(videos.count, 3)
        XCTAssertNil(videos[0].recommendationTarget)
        guard case .live(let room) = videos[1].recommendationTarget else { return XCTFail("直播卡") }
        XCTAssertEqual(room.roomID, 7736134)
        XCTAssertEqual(room.username, "主播")
        XCTAssertEqual(videos[1].bvid, "live-7736134")
        XCTAssertEqual(videos[1].coverCornerText, "直播")
        XCTAssertTrue(videos[1].canDisplayVideo(hidingPortrait: true), "直播卡不受竖屏过滤影响")
        XCTAssertEqual(videos[2].recommendationTarget, .dynamic(id: "987654321"))
        XCTAssertEqual(videos[2].owner.name, "作者")
        XCTAssertEqual(videos[2].recommendationBadge, "动态")
        XCTAssertEqual(AppRecommendationCard.dynamicID(from: "bilibili://opus/detail/42?x=1"), "42")
        XCTAssertNil(AppRecommendationCard.dynamicID(from: "bilibili://article/42"))
    }

    func testLocalFiltersMatchPiliPlusRules() throws {
        var liked = card; liked["rcmd_reason"] = "1万点赞"          // 12.5万播放，点赞率 8%
        var followed = card; followed["rcmd_reason"] = "已关注"; followed["title"] = "广告测试"
        var zone = card; zone["args"] = ["up_id": 1, "up_name": "A", "tname": "鬼畜调教"]
        var short = card; short["player_args"] = ["aid": 170001, "cid": 1, "duration": 20]
        let page = try decode([liked, followed, zone, short])
        XCTAssertEqual(page.cards[0].like, 10_000)
        XCTAssertTrue(page.cards[1].isFollowed)
        XCTAssertEqual(page.cards[0].video.recommendationBadge, "1万点赞")
        XCTAssertEqual(page.cards[1].video.recommendationBadge, "已关注")
        XCTAssertNil(page.cards[2].video.recommendationBadge)

        var filter = RecommendationFilter()
        filter.minLikeRatio = 4
        filter.minDuration = 30
        filter.titleBanWord = RecommendationFilter.pattern("广告|推广")
        filter.zoneBanWord = RecommendationFilter.pattern("鬼畜")
        // 点赞率 8% 保留；已关注豁免标题过滤；分区命中和太短的都去掉。
        XCTAssertEqual(page.videos(filter: filter).map(\.title), ["测试视频", "广告测试"])
        filter.exemptFollowed = false
        XCTAssertEqual(page.videos(filter: filter).map(\.title), ["测试视频"])
        filter.minPlay = 200_000
        XCTAssertTrue(page.videos(filter: filter).isEmpty)
    }

    func testWebCardsKeepOnlyVideosAndUseExactCounters() throws {
        let video: [String: Any] = ["goto": "av", "id": 170001, "bvid": "BV17x411w7KC", "cid": 279786,
                                    "title": "网页视频", "pic": "https://example.com/p.jpg", "duration": 90,
                                    "owner": ["mid": 42, "name": "UP", "face": ""], "is_followed": 1,
                                    "stat": ["view": 1000, "like": 5, "danmaku": 3]]
        var live = video; live["goto"] = "live"
        var noOwner = video; noOwner["owner"] = NSNull()
        let data = try JSONSerialization.data(withJSONObject: ["item": [live, noOwner, video]])
        let page = try JSONDecoder().decode(WebRecommendationPage.self, from: data)
        XCTAssertEqual(page.cards.count, 1)
        XCTAssertTrue(page.cards[0].isFollowed)
        XCTAssertTrue(page.cards[0].video.isWebRecommendation)
        XCTAssertEqual(page.cards[0].video.recommendationBadge, "已关注")
        var filter = RecommendationFilter()
        filter.minLikeRatio = 1                       // 点赞率 0.5%
        XCTAssertEqual(page.videos(filter: filter).count, 1, "已关注默认豁免")
        filter.exemptFollowed = false
        XCTAssertTrue(page.videos(filter: filter).isEmpty)
        XCTAssertEqual(WebRecommendationPage.parameters(freshIndex: 3)["brush"], "3")
    }

    func testBlockedOwnersAndMissingCidFollowPiliPlus() throws {
        var noCid = card; noCid["player_args"] = ["aid": 170001, "duration": 30]
        var other = card; other["param"] = "170002"; other["player_args"] = ["aid": 170002, "cid": 1, "duration": 30]
        other["args"] = ["up_id": 7, "up_name": "别人"]
        let page = try decode([noCid, other])
        XCTAssertEqual(page.videos.map(\.cid), [0, 1], "缺 cid 的视频卡保留，点开时再查")
        var filter = RecommendationFilter()
        filter.blockedMids = [42]
        XCTAssertEqual(page.videos(filter: filter).map(\.owner.mid), [7])
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        RecommendationFilter.block(42, defaults: defaults)
        XCTAssertEqual(RecommendationFilter.current(defaults).blockedMids, [42])
    }

    func testOnlyConnectionFailuresAreRetried() {
        XCTAssertTrue(APIClient.isRetryable(URLError(.timedOut)))
        XCTAssertTrue(APIClient.isRetryable(URLError(.notConnectedToInternet)))
        XCTAssertFalse(APIClient.isRetryable(URLError(.networkConnectionLost)), "中途断开时请求可能已到服务端")
        XCTAssertFalse(APIClient.isRetryable(URLError(.cancelled)))
    }

    func testAppRecommendationUsesSigningClientInHeaders() {
        let headers = AppRecommendationPage.headers(buvid: "b")
        XCTAssertEqual(headers["app-key"], "iphone")
        XCTAssertTrue(headers["User-Agent"]?.contains("mobi_app/iphone") == true)
        XCTAssertNil(headers["bili-http-engine"])
    }

    func testAuroraEIDMatchesPiliPlus() {
        XCTAssertEqual(BiliHeaders.auroraEID(mid: 1), "UA")
        XCTAssertNil(BiliHeaders.appAccountHeaders(mid: nil)["x-bili-mid"])
        XCTAssertEqual(BiliHeaders.appAccountHeaders(mid: 42)["app-key"], "iphone")
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
        let params = AppRecommendationPage.parameters(for: RecommendationRequest(source: .app, pageIndex: 1, appCursor: 123))
        XCTAssertEqual(params["idx"], "123")
        XCTAssertEqual(params["mobi_app"], "iphone")
        XCTAssertEqual(params["platform"], "ios")
        XCTAssertNil(AppRecommendationPage.headers(buvid: "b")["fp_local"])
        XCTAssertEqual(AppRecommendationPage.traceID().split(separator: ":").map(\.count), [32, 16, 1, 1])
        XCTAssertNil(params["fresh_idx"])
        XCTAssertEqual(params["pull"], "0")
        XCTAssertEqual(params["flush"], "8")
        XCTAssertEqual(AppRecommendationPage.count("1.2亿"), 120_000_000)
        XCTAssertNil(AppRecommendationPage.bvid(aid: -1))
    }

    func testInitialRefreshAndPaginationParametersUseCapturedProtocolWithoutChangingIdentity() {
        let initial = RecommendationRequest(source: .app)
        let refresh = RecommendationRequest(source: .app, isRefresh: true)
        let requests = [initial, refresh, refresh.next(appCursor: 456)]
        let params = requests.map { AppRecommendationPage.parameters(for: $0) }
        XCTAssertEqual(params.map { $0["flush"] }, ["0", "6", "8"])
        XCTAssertEqual(params.map { $0["pull"] }, ["1", "1", "0"])
        XCTAssertEqual(params.map { $0["idx"] }, ["0", "0", "456"])
        for value in params {
            for (key, identity) in AppClientIdentity.parameters { XCTAssertEqual(value[key], identity) }
            XCTAssertEqual(value["actionKey"], "appkey")
            XCTAssertEqual(value["c_locale"], "zh-Hans_CN")
            XCTAssertEqual(value["s_locale"], "zh-Hans_CN")
            XCTAssertEqual(value["fnval"], "84948", "Recommendation comparison policy, separate from playback capabilities")
            XCTAssertEqual(value["device_name"], AppClientIdentity.deviceName)
            for field in ["player_extra_content", "ad_extra", "access_key", "network", "widgets"] {
                XCTAssertNil(value[field], "Do not fabricate or copy dynamic state: \(field)")
            }
        }
    }

    func testPlayerExtraContentUsesActualPixelsAndIsOrientationIndependent() throws {
        let portrait = try XCTUnwrap(AppRecommendationDisplay(width: 1206, height: 2622))
        let landscape = try XCTUnwrap(AppRecommendationDisplay(width: 2622, height: 1206))
        XCTAssertEqual(portrait.playerExtraContent, #"{"short_edge":"1206","long_edge":"2622"}"#)
        XCTAssertEqual(landscape.playerExtraContent, portrait.playerExtraContent)
        let small = try XCTUnwrap(AppRecommendationDisplay(width: 750, height: 1334))
        let params = AppRecommendationPage.parameters(for: .init(source: .app), display: small)
        XCTAssertEqual(params["player_extra_content"], #"{"short_edge":"750","long_edge":"1334"}"#)
        for size in [0.0, -1, Double.infinity, Double.nan, Double(Int.max)] {
            XCTAssertNil(AppRecommendationDisplay(width: size, height: 100))
        }
        XCTAssertEqual(AppRecommendationPlaybackCapabilities.fnval & 16384, 0, "HDR Vivid is unverified")
        XCTAssertEqual(AppRecommendationPlaybackCapabilities.fnval & 65536, 0, "Do not claim unknown private bits")
    }

    func testCursorIsReadBeforeCardValidationAndLocalFiltering() throws {
        var valid = card; valid["idx"] = 1_745_482_992
        var ad = card; ad["idx"] = "1745482980"; ad["ad_info"] = ["id": 1]
        let malformed: [String: Any] = ["idx": 1_745_482_970, "player_args": "broken"]
        let page = try decode([valid, ad, malformed, ["idx": NSNull()], ["idx": "invalid"]])
        XCTAssertEqual(page.videos.count, 1)
        XCTAssertEqual(page.nextCursor, 1_745_482_970, "Use response order, not maximum idx or last visible card")
        var filter = RecommendationFilter()
        filter.blockedMids = [42]
        let batch = page.batch(for: RecommendationRequest(source: .app), filter: filter)
        XCTAssertTrue(batch.videos.isEmpty)
        XCTAssertEqual(batch.nextRequest?.appCursor, 1_745_482_970)
        XCTAssertEqual(batch.nextRequest?.pageIndex, 1)
    }

    func testMissingInvalidOrRepeatedCursorStopsPaginationWithoutDroppingVideos() throws {
        let request = RecommendationRequest(source: .app, pageIndex: 1, appCursor: 123)
        for idx: Any in [NSNull(), "bad", -1, 0, 1.5, "999999999999999999999999999", 123] {
            var value = card; value["idx"] = idx
            let batch = try decode([value]).batch(for: request, filter: .none)
            XCTAssertEqual(batch.videos.count, 1)
            XCTAssertNil(batch.nextRequest)
        }
        XCTAssertNil(try decode([card]).nextCursor)
        XCTAssertNil(try decode([]).batch(for: request, filter: .none).nextRequest)
    }

    /// 只读烟雾验证：直接访问 App 推荐，不允许热门兜底掩盖接口或解析错误。
    func testAppEndpointReturnsPlayableCardsOverNetwork() async throws {
        try XCTSkipUnless(!AppNetwork.isRegression && ProcessInfo.processInfo.environment["NEOBILI_NETWORK_SMOKE"] == "1", "显式联网验收")
        let hasAppCredential = await DeviceIdentity.shared.accessKey?.isEmpty == false
        var request = RecommendationRequest(source: .app)
        var seen: Set<String> = []
        for page in 0..<3 {
            let batch = try await BiliAPI.appRecommendFeed(request: request)
            let videos = batch.videos
            let duplicates = videos.filter { seen.contains($0.bvid) }.count
            print("AppRecommendationSmoke: page=\(page), cards=\(videos.count), duplicates=\(duplicates), appCredential=\(hasAppCredential), hasNext=\(batch.nextRequest != nil), refreshActive=\(batch.refreshConfig?.active ?? -1), refreshAppear=\(batch.refreshConfig?.appear ?? -1), refreshBehavior=\(batch.refreshConfig?.behavior ?? -1)")
            XCTAssertFalse(videos.isEmpty)
            XCTAssertTrue(videos.filter { $0.recommendationTarget == nil }.allSatisfy { $0.aid > 0 && $0.bvid.hasPrefix("BV") })
            seen.formUnion(videos.map(\.bvid))
            request = try XCTUnwrap(batch.nextRequest, "Server must return a usable cursor for pagination")
        }
    }

    private var card: [String: Any] {
        ["goto": "av", "card_goto": "av", "can_play": 1, "param": "170001",
         "title": "测试视频", "cover": "https://example.com/cover.jpg",
         "player_args": ["aid": 170001, "cid": 279786, "duration": 180],
         "args": ["up_id": 42, "up_name": "测试 UP"],
         "three_point_v2": [["type": "watch_later"],
                            ["type": "dislike", "reasons": [["id": 1, "name": "不感兴趣", "toast": "将减少相似内容推荐"]]],
                            ["type": "feedback", "reasons": [["id": 2, "name": "内容引起不适", "toast": "感谢反馈"]]]],
         "cover_left_text_1": "12.5万", "cover_left_text_2": "345"]
    }
    private func decode(_ items: [[String: Any]]) throws -> AppRecommendationPage {
        try JSONDecoder().decode(AppRecommendationPage.self, from: JSONSerialization.data(withJSONObject: ["items": items]))
    }
}
