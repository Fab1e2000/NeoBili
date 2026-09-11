import XCTest
@testable import NeoBili

final class LiveAPITests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testEnvelopeAcceptsNumericMessageAndPreservesLoginAndRiskErrors() throws {
        let success = try decode(LiveResponse<Int>.self, #"{"code":0,"message":0,"data":7}"#)
        XCTAssertEqual(try success.value(), 7)
        let login = try decode(LiveResponse<LiveListingPayload>.self, #"{"code":-101,"message":"账号未登录","data":[]}"#)
        XCTAssertThrowsError(try login.value()) { error in
            guard case BiliAPIError.apiError(let code, _) = error else { return XCTFail("Should retain API failure") }
            XCTAssertEqual(code, -101)
        }
        let risk = try decode(LiveResponse<LiveListingPayload>.self, #"{"code":-352,"message":"-352","data":null}"#)
        XCTAssertThrowsError(try risk.value()) { error in
            guard case BiliAPIError.riskControlled = error else { return XCTFail("Must not hide risk control") }
        }
    }

    func testRoomAliasesMixedIDsAndHTTPSImages() throws {
        let room = try decode(LiveRoom.self, #"{"roomid":"123","uid":"45","title":"直播","uname":"主播A","room_cover":"//i0.hdslb.com/live.jpg","face":"http://i1.hdslb.com/face.jpg","online":"999","area_name":"音乐","live_status":0}"#)
        XCTAssertEqual(room.roomID, 123)
        XCTAssertEqual(room.uid, 45)
        XCTAssertEqual(room.username, "主播A")
        XCTAssertEqual(room.online, 999)
        XCTAssertEqual(room.coverURL?.scheme, "https")
        XCTAssertEqual(room.avatarURL?.scheme, "https")
        XCTAssertFalse(room.isLive)
        XCTAssertThrowsError(try decode(LiveRoom.self, #"{"roomid":0,"title":"广告"}"#))
    }

    func testFollowingFiltersOfflineRoomsWithoutLosingPagination() throws {
        let payload = try decode(LiveListingPayload.self, #"{"list":[{"roomid":1,"live_status":0},{"roomid":2,"live_status":1},{"roomid":2,"live_status":1},{"card_type":"ad"}],"totalPage":3,"count":22}"#)
        let page = payload.page(number: 1, size: 9, onlyLive: true)
        XCTAssertEqual(page.rooms.map(\.id), [2])
        XCTAssertEqual(page.sourceRoomIDs, [1, 2], "Keep offline IDs for pagination-loop detection after filtering")
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.total, 22)
        XCTAssertFalse(payload.page(number: 3, size: 9, onlyLive: true).hasMore)
    }

    func testExplicitHasMoreWinsOverCountAndKeepsAllValidRooms() throws {
        let payload = try decode(LiveListingPayload.self, #"{"list":[{"room_id":9},{"room_id":10}],"has_more":1,"count":2}"#)
        XCTAssertTrue(payload.page(number: 1, size: 20).hasMore)
        XCTAssertEqual(payload.page(number: 1, size: 20).rooms.map(\.roomID), [9, 10])
    }

    func testAppFeedExtractsRoomCardsAndPreservesPagination() throws {
        let payload = try decode(LiveAppFeedPayload.self, #"""
        {"card_list":[
          {"card_type":"banner_v2","card_data":{"banner_v2":{"list":[{"id":55}]}}},
          {"card_type":"my_idol_v1","card_data":{"my_idol_v1":{"list":[{"roomid":66}]}}},
          {"card_type":"small_card_v1","card_data":{"small_card_v1":{"roomid":"123","uname":"主播A","title":"直播A"}}},
          {"card_type":"small_card_v1","card_data":{"small_card_v1":{"id":456,"uname":"主播B"}}},
          {"card_type":"small_card_v1","card_data":{"small_card_v1":{"roomid":123}}},
          {"card_type":"small_card_v1","card_data":{"small_card_v1":{"roomid":0}}},
          {"card_type":"small_card_v1","card_data":null}, null,
          {"card_type":"area_entrance_v3","card_data":{"area_entrance_v3":{"list":[{"id":77}]}}}
        ],"has_more":1}
        """#)
        let page = payload.page(number: 2)
        XCTAssertEqual(page.rooms.map(\.roomID), [123, 456])
        XCTAssertEqual(page.rooms.first?.username, "主播A")
        XCTAssertEqual(page.page, 2)
        XCTAssertTrue(page.hasMore)
        let finished = try decode(LiveAppFeedPayload.self, #"{"card_list":[],"has_more":0}"#)
        XCTAssertFalse(finished.page(number: 1).hasMore)
        XCTAssertTrue(finished.rooms.isEmpty)
    }

    func testAppFeedKeepsExistingAndroidHDIdentityAndExactSignedQuery() throws {
        let url = try LiveAPI.makeAppFeedURL(page: 0, accessKey: "test+a&b", timestamp: 123456)
        XCTAssertEqual(url.path, "/xlive/app-interface/v2/index/feed")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(query["appkey"], AppSigner.appKey)
        XCTAssertEqual(query["access_key"], "test+a&b")
        XCTAssertEqual(query["mobi_app"], "android_hd")
        XCTAssertEqual(query["build"], "2001100")
        XCTAssertEqual(query["device"], "android")
        XCTAssertEqual(query["device_name"], "android")
        XCTAssertEqual(query["device_type"], "0")
        XCTAssertEqual(query["network"], "wifi")
        XCTAssertEqual(query["scale"], "2")
        XCTAssertEqual(query["statistics"], #"{"appId":5,"platform":3,"version":"2.0.1","abtest":""}"#)
        XCTAssertEqual(query["relation_page"], "1")
        XCTAssertNil(query["module_select"])
        XCTAssertEqual(query["page"], "1")
        XCTAssertEqual(query["ts"], "123456")
        XCTAssertNil(query["fp_local"])
        XCTAssertNil(query["fp_remote"])
        XCTAssertNil(query["session_id"])
        XCTAssertEqual(query["sign"], AppSigner.signed(query, timestamp: 123456)["sign"])
        XCTAssertEqual(components.percentEncodedQuery, AppSigner.queryString(from: query))
    }

    func testAppFeedAnonymousProbeOmitsAccountAndOptionalModuleDefaults() throws {
        let url = try LiveAPI.makeAppFeedURL(page: 1, accessKey: nil, moduleSelect: true, timestamp: 123456)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        XCTAssertNil(query["access_key"])
        XCTAssertNil(query["relation_page"])
        XCTAssertEqual(query["module_select"], "1")
        XCTAssertEqual(query["sign"], AppSigner.signed(query, timestamp: 123456)["sign"])
    }

    func testRoomInfoMergesAnchorAndCanonicalRoomID() throws {
        let payload = try decode(LiveRoomInfoPayload.self, #"{"room_info":{"room_id":7734200,"uid":50329118,"title":"赛事直播","live_status":1,"cover":"https://i0.hdslb.com/room.jpg","description":"介绍"},"anchor_info":{"base_info":{"uname":"官方赛事","face":"https://i0.hdslb.com/face.jpg"}},"news_info":{"content":"直播公告"}}"#)
        XCTAssertEqual(payload.room.roomID, 7734200)
        XCTAssertEqual(payload.room.username, "官方赛事")
        XCTAssertEqual(payload.room.description, "介绍")
        XCTAssertEqual(payload.room.announcement, "直播公告")
        XCTAssertTrue(payload.room.isLive)
    }

    func testPlaybackUsesServerQualitySignedURLAndCompatibleHLSFirst() throws {
        let playback = try decode(LivePlaybackPayload.self, Self.playbackFixture).playback(fallbackRoomID: 6)
        XCTAssertEqual(playback.roomID, 7734200)
        XCTAssertEqual(playback.qualities.map(\.id), [400, 250])
        XCTAssertEqual(playback.qualities.map(\.name), ["蓝光", "超清"])
        XCTAssertEqual(playback.candidates.count, 2)
        XCTAssertEqual(playback.candidates.first?.formatName, "ts")
        XCTAssertEqual(playback.candidates.first?.codecName, "avc")
        XCTAssertEqual(playback.candidates.first?.quality, 250,
                       "服务端降级时使用实际current_qn，不能把请求原画当成已得到原画")
        XCTAssertEqual(playback.candidates.first?.url.absoluteString, "https://cdn.example.invalid/live/test.m3u8?token=a%2Bb&qn=250")
        XCTAssertEqual(playback.candidates.first?.headers["Referer"], "https://live.bilibili.com/7734200")
    }

    func testOfflineRoomNeedsNoPlayURLAndCannotPublishOldCandidates() throws {
        let offline = try decode(LivePlaybackPayload.self, #"{"room_id":12,"live_status":0,"playurl_info":null}"#)
            .playback(fallbackRoomID: 6)
        XCTAssertFalse(offline.isLive)
        XCTAssertTrue(offline.candidates.isEmpty)
        let ended = try decode(LivePlaybackPayload.self, Self.playbackFixture.replacingOccurrences(of: "\"live_status\":1", with: "\"live_status\":0"))
            .playback(fallbackRoomID: 6)
        XCTAssertTrue(ended.candidates.isEmpty)
    }

    func testPlaybackQueryEncodingMatchesWBISignedBytes() throws {
        let url = try LiveAPI.makeURL(path: "xlive/web-room/v2/index/getRoomPlayInfo", params: [
            "room_id": "6", "protocol": "0,1", "probe": "a+b/@:"
        ])
        XCTAssertEqual(url.host, "api.live.bilibili.com")
        XCTAssertTrue(url.absoluteString.contains("protocol=0%2C1"))
        XCTAssertTrue(url.absoluteString.contains("probe=a%2Bb%2F%40%3A"))
    }

    private static let playbackFixture = #"""
    {"room_id":7734200,"live_status":1,"is_portrait":false,"playurl_info":{"playurl":{
      "g_qn_desc":[{"qn":10000,"desc":"原画"},{"qn":400,"desc":"蓝光"},{"qn":250,"desc":"超清"}],
      "stream":[
        {"protocol_name":"http_stream","format":[{"format_name":"flv","codec":[{
          "codec_name":"avc","current_qn":250,"accept_qn":[400,250],"base_url":"/live/test.flv",
          "url_info":[{"host":"https://cdn.example.invalid","extra":"?token=abc"}]
        }]}]},
        {"protocol_name":"http_hls","format":[{"format_name":"ts","codec":[{
          "codec_name":"avc","current_qn":250,"accept_qn":[400,250],"base_url":"/live/test.m3u8",
          "url_info":[{"host":"https://cdn.example.invalid","extra":"?token=a%2Bb&qn=250"},
                      {"host":"https://cdn.example.invalid","extra":"?token=a%2Bb&qn=250"},
                      {"host":"file://invalid","extra":""}]
        }]}]}
      ]
    }}}
    """#
}
