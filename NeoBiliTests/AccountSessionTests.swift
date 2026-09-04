import XCTest
@testable import NeoBili

final class AccountSessionTests: XCTestCase {
    // MARK: - 登录 Cookie 拼接

    @MainActor
    func testCookieHeaderCarriesLoginCredentials() async {
        let identity = DeviceIdentity.shared
        await identity.setLoginCookies(
            sessdata: "abc%2Cdef123",
            biliJct: "csrf456",
            dedeUserID: "10000"
        )
        defer {
            Task { await identity.clearLoginCookies() }
        }

        let header = await identity.cookieHeader()
        XCTAssertTrue(header.contains("SESSDATA=abc%2Cdef123"), "SESSDATA 原样发送，不做二次转义")
        XCTAssertTrue(header.contains("bili_jct=csrf456"))
        XCTAssertTrue(header.contains("DedeUserID=10000"))
        let loggedIn = await identity.isLoggedIn
        XCTAssertTrue(loggedIn)
        let csrf = await identity.csrfToken
        XCTAssertEqual(csrf, "csrf456")
    }

    @MainActor
    func testClearingCookiesRemovesLoginState() async {
        let identity = DeviceIdentity.shared
        await identity.setLoginCookies(sessdata: "a", biliJct: "b", dedeUserID: "c")
        await identity.clearLoginCookies()

        let header = await identity.cookieHeader()
        XCTAssertFalse(header.contains("SESSDATA="))
        let loggedIn = await identity.isLoggedIn
        XCTAssertFalse(loggedIn)
    }

    // MARK: - 历史条目

    func testHistoryItemFiltersNonArchiveAndBuildsKid() throws {
        let json = """
        [
          {"title":"某个视频","long_title":"","cover":"http://i0.hdslb.com/x.jpg",
           "duration":300,"author_name":"UP主","view_at":1700000000,"progress":95,
           "history":{"business":"archive","oid":12345,"bvid":"BV1xx","cid":777,"type":3}},
          {"title":"某场直播","long_title":"","cover":"","duration":0,
           "history":{"business":"live","oid":999,"bvid":"","cid":0,"type":9}}
        ]
        """
        let items = try JSONDecoder().decode([HistoryItem].self, from: Data(json.utf8))

        XCTAssertEqual(items.count, 2)
        let video = try XCTUnwrap(items.first)
        // 删除接口要的是「业务名_条目号」。这条断言原先写的是 "3_12345"（拿 type
        // 当前缀），把一个会让服务端回 -400 的格式当成了正确答案。
        XCTAssertEqual(video.kidParam, "archive_12345")
        XCTAssertTrue(video.isVideo)
        XCTAssertEqual(video.asVideoSummary?.cid, 777)
        XCTAssertEqual(video.asVideoSummary?.bvid, "BV1xx")

        let live = try XCTUnwrap(items.last)
        XCTAssertFalse(live.isVideo)
        XCTAssertNil(live.asVideoSummary)
    }

    // MARK: - 收藏条目

    func testFavMediaOnlyMapsVideoEntries() throws {
        let json = """
        [{"id":42,"bvid":"BV1fav","type":2,"title":"收藏的视频","cover":"http://i0.hdslb.com/y.jpg",
          "duration":120,"cnt_info":{"play":1000,"danmaku":10},"upper":{"mid":7,"name":"UP","face":""}},
         {"id":43,"bvid":"","type":24,"title":"某课程","cover":"","duration":0}]
        """
        let medias = try JSONDecoder().decode([FavMedia].self, from: Data(json.utf8))

        let video = try XCTUnwrap(medias.first)
        XCTAssertTrue(video.isVideo)
        let summary = try XCTUnwrap(video.asVideoSummary)
        XCTAssertEqual(summary.bvid, "BV1fav")
        // 收藏接口不带 cid；调用方必须把 0 视为「无 cid」传 nil。
        XCTAssertEqual(summary.cid, 0)

        let course = try XCTUnwrap(medias.last)
        XCTAssertFalse(course.isVideo)
        XCTAssertNil(course.asVideoSummary)
    }

    // MARK: - 扫码轮询状态解析

    func testQRPollReadsBusinessCodeFromDataNotEnvelope() throws {
        // 顶层 code 恒为 0，业务状态在 data.code —— 读错位置会把未扫码误判成已确认。
        let waiting = Data(#"{"code":0,"message":"0","data":{"url":"","refresh_token":"","timestamp":1,"code":86101,"message":"未扫码"}}"#.utf8)
        if case .waiting = try BiliPassport.pollOutcome(fromPayload: waiting, cookies: nil) {} else {
            XCTFail("86101 应解析为 waiting")
        }

        let scanned = Data(#"{"code":0,"message":"0","data":{"url":"","refresh_token":"","timestamp":1,"code":86090,"message":"已扫码未确认"}}"#.utf8)
        if case .scanned = try BiliPassport.pollOutcome(fromPayload: scanned, cookies: nil) {} else {
            XCTFail("86090 应解析为 scanned")
        }

        let expired = Data(#"{"code":0,"message":"0","data":{"url":"","refresh_token":"","timestamp":1,"code":86038,"message":"二维码已失效"}}"#.utf8)
        if case .expired = try BiliPassport.pollOutcome(fromPayload: expired, cookies: nil) {} else {
            XCTFail("86038 应解析为 expired")
        }

        // data.code == 0 表示确认成功，但凭据在 Set-Cookie 头里；没带凭据必须报错，
        // 而不是把「未扫码」当成功。
        let confirmed = Data(#"{"code":0,"message":"0","data":{"url":"https://passport.bilibili.com","refresh_token":"","timestamp":1,"code":0,"message":""}}"#.utf8)
        XCTAssertThrowsError(try BiliPassport.pollOutcome(fromPayload: confirmed, cookies: nil))
        if case .confirmed(let cookies, _) = try BiliPassport.pollOutcome(
            fromPayload: confirmed,
            cookies: BiliPassport.LoginCookies(sessdata: "s", biliJct: "j", dedeUserID: "1")
        ) {
            XCTAssertEqual(cookies.sessdata, "s")
        } else {
            XCTFail("带凭据时应解析为 confirmed")
        }
    }

    // MARK: - 收藏夹 / 历史响应解包

    func testFavFolderListUnwrapsDataList() throws {
        // list-all 的 data 是 {"count", "list"}，不是裸数组。
        let json = """
        {"count":1,"list":[{"id":123456,"fid":0,"mid":7,"title":"默认收藏夹","media_count":3}]}
        """
        let payload = try JSONDecoder().decode(FavFolderList.self, from: Data(json.utf8))
        XCTAssertEqual(payload.list?.first?.id, 123456)
        XCTAssertEqual(payload.list?.first?.mediaCount, 3)
    }

    func testHistoryPageReadsListKey() throws {
        // 历史接口的条目在 data.list（文档写的 items 实际不返回）。
        let json = """
        {"cursor":{"max":-1,"view_at":1700000000,"ps":20},
         "list":[{"title":"某个视频","cover":"http://i0.hdslb.com/x.jpg","duration":300,
                  "author_name":"UP主","view_at":1700000000,"progress":95,"kid":12345,
                  "history":{"business":"archive","oid":12345,"bvid":"BV1xx","cid":777}}]}
        """
        let page = try JSONDecoder().decode(HistoryCursorPage.self, from: Data(json.utf8))
        XCTAssertEqual(page.allItems.count, 1)
        XCTAssertEqual(page.allItems.first?.kidParam, "archive_12345", "条目自带的 kid 优先，前缀仍是业务名")
        XCTAssertEqual(page.cursor?.resolvedViewAt, 1700000000)
    }

    func testHistoryItemWithoutDirectKidFallsBackToOid() throws {
        let json = """
        {"title":"某个视频","history":{"business":"archive","oid":12345,"bvid":"BV1xx","cid":777}}
        """
        let item = try JSONDecoder().decode(HistoryItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.kidParam, "archive_12345")
    }

    // MARK: - 稍后再看

    func testWatchLaterItemDecodesOwnerKey() throws {
        // toview/web 变体的 UP 主信息在 `owner` 键（与视频详情一致），不在 `upper`。
        let json = """
        {"aid":99,"bvid":"BV1later","cid":55,"title":"稍后再看的视频","pic":"http://i0.hdslb.com/z.jpg",
         "duration":180,"add_at":1700000000,
         "owner":{"mid":7,"name":"UP主","face":"http://i0.hdslb.com/face.jpg"}}
        """
        let item = try JSONDecoder().decode(WatchLaterItem.self, from: Data(json.utf8))
        let summary = try XCTUnwrap(item.asVideoSummary, "有 owner 时必须能映射出视频卡片")
        XCTAssertEqual(summary.bvid, "BV1later")
        XCTAssertEqual(summary.owner.name, "UP主")

        // 老接口的 upper 键也要兼容。
        let legacy = """
        {"aid":100,"bvid":"BV1old","cid":56,"title":"老结构","upper":{"mid":8,"name":"老UP","face":""}}
        """
        let oldItem = try JSONDecoder().decode(WatchLaterItem.self, from: Data(legacy.utf8))
        XCTAssertNotNil(oldItem.asVideoSummary)
    }

    // MARK: - 展示工具
}
