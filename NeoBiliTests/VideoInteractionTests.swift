import XCTest
@testable import NeoBili

/// 视频页互动功能依赖的两块基础设施：APP 端签名，和几个新增响应体的解码。
///
/// 签名一旦算错，服务端只会回一句「API 校验密匙错误」，从网络日志上看不出是
/// 哪一步偏了，所以这里用固定时间戳把整条算式钉死。
final class VideoInteractionTests: XCTestCase {
    // MARK: - APP 端签名

    func testAppSignMatchesReferenceQuery() {
        let signed = AppSigner.signed(
            ["auth_code": "abc", "local_id": "0"],
            timestamp: 1_700_000_000
        )

        XCTAssertEqual(signed["appkey"], "dfca71928277209b")
        XCTAssertEqual(signed["ts"], "1700000000")
        XCTAssertEqual(signed["sign"], "77ac440a7f4c033d8f62ea07505fa64f")
    }

    /// 参与签名的串必须按参数名排序，而且要用 `encodeURIComponent` 的转义规则
    /// （`/`、`+`、空格都得转义）。用 Foundation 默认的 urlQueryAllowed 会漏掉
    /// 其中几个，签名就对不上了。
    func testAppSignEncodesReservedCharactersAndSortsKeys() {
        let params = [
            "aid": "114514",
            "dislike": "1",
            "access_key": "key/with+special chars"
        ]
        let signed = AppSigner.signed(params, timestamp: 1_700_000_000)

        let query = AppSigner.queryString(from: signed.filter { $0.key != "sign" })
        XCTAssertEqual(
            query,
            "access_key=key%2Fwith%2Bspecial%20chars&aid=114514&appkey=dfca71928277209b&dislike=1&ts=1700000000"
        )
        XCTAssertEqual(signed["sign"], "5859cba7a4fe8d5c9f98bb467fa1e801")
    }

    /// 重复签名不该把上一次的 sign 也算进去。
    func testAppSignIgnoresPreviousSignature() {
        let once = AppSigner.signed(["aid": "1"], timestamp: 1_700_000_000)
        let twice = AppSigner.signed(once, timestamp: 1_700_000_000)
        XCTAssertEqual(once["sign"], twice["sign"])
    }

    // MARK: - App 扫码轮询

    func testAppQRPollExtractsCookiesAndAccessKey() throws {
        let payload = Data(#"""
        {"code":0,"message":"0","data":{"mid":1,"access_token":"tv-token","refresh_token":"r",
        "expires_in":1,"cookie_info":{"cookies":[
        {"name":"SESSDATA","value":"sess%2Cdata"},
        {"name":"bili_jct","value":"csrf"},
        {"name":"DedeUserID","value":"10000"}]}}}
        """#.utf8)

        guard case .confirmed(let cookies, let accessKey) = try BiliPassport.appPollOutcome(fromPayload: payload) else {
            return XCTFail("code 0 应解析为 confirmed")
        }
        XCTAssertEqual(cookies.sessdata, "sess%2Cdata")
        XCTAssertEqual(cookies.biliJct, "csrf")
        XCTAssertEqual(cookies.dedeUserID, "10000")
        XCTAssertEqual(accessKey, "tv-token")
    }

    func testAppQRPollMapsPendingAndExpired() throws {
        let pending = Data(#"{"code":86039,"message":"二维码尚未确认","data":null}"#.utf8)
        guard case .waiting = try BiliPassport.appPollOutcome(fromPayload: pending) else {
            return XCTFail("86039 应解析为 waiting")
        }

        let expired = Data(#"{"code":86038,"message":"二维码已失效","data":null}"#.utf8)
        guard case .expired = try BiliPassport.appPollOutcome(fromPayload: expired) else {
            return XCTFail("86038 应解析为 expired")
        }
    }

    /// code 0 但没带下 Cookie 时不能当成登录成功，否则会写入一份空凭据。
    func testAppQRPollWithoutCookiesThrows() {
        let payload = Data(#"{"code":0,"message":"0","data":{"access_token":"t"}}"#.utf8)
        XCTAssertThrowsError(try BiliPassport.appPollOutcome(fromPayload: payload))
    }

    // MARK: - 新增响应体解码

    /// 合集字段一律可选：缺字段只该让合集入口不显示，不该让整个视频详情解析失败。
    func testUgcSeasonDecodesAndFlattensEpisodes() throws {
        let json = Data(#"""
        {"bvid":"BV1","aid":1,"cid":2,"title":"t","desc":"d","pic":"p","duration":1,
        "pubdate":1700000000,"copyright":1,"tname":"影视",
        "owner":{"mid":9,"name":"up","face":"f"},
        "stat":{"view":1,"danmaku":2,"like":3,"favorite":4,"coin":5,"share":6,"reply":7},
        "pages":[{"cid":2,"page":1,"part":"P1","duration":1}],
        "ugc_season":{"id":77,"title":"日恐","sections":[
        {"id":1,"episodes":[{"id":11,"aid":1,"cid":2,"bvid":"BV1","title":"第一集",
        "arc":{"pic":"c1","duration":125}}]},
        {"id":2,"episodes":[{"id":12,"aid":2,"cid":3,"bvid":"BV2","title":"第二集"}]}]}}
        """#.utf8)

        let detail = try JSONDecoder().decode(VideoDetail.self, from: json)
        XCTAssertEqual(detail.tname, "影视")
        XCTAssertEqual(detail.copyright, 1)

        let season = try XCTUnwrap(detail.ugcSeason)
        XCTAssertEqual(season.title, "日恐")
        // 两个 section 的分集会被拉平成一个列表。
        XCTAssertEqual(season.episodes.map(\.bvid), ["BV1", "BV2"])
        XCTAssertEqual(season.episodes[0].formattedDuration, "2:05")
        // arc 缺失时时长为空串，界面据此不画时长角标。
        XCTAssertEqual(season.episodes[1].formattedDuration, "")
    }

    func testVideoDetailWithoutOptionalFieldsStillDecodes() throws {
        let json = Data(#"""
        {"bvid":"BV1","aid":1,"cid":2,"title":"t","desc":"d","pic":"p","duration":1,
        "pubdate":1,"owner":{"mid":9,"name":"up","face":"f"},
        "stat":{"view":1,"danmaku":2,"like":3,"favorite":4,"coin":5,"share":6,"reply":7},
        "pages":[]}
        """#.utf8)

        let detail = try JSONDecoder().decode(VideoDetail.self, from: json)
        XCTAssertNil(detail.ugcSeason)
        XCTAssertNil(detail.tname)
        XCTAssertNil(detail.copyright)
    }

    /// `coin` 是数字而不是布尔值，五个按钮的高亮都从这一份响应推出来。
    func testVideoRelationDecodesMixedTypes() throws {
        let json = Data(#"""
        {"attention":true,"favorite":false,"season_fav":false,"like":true,"dislike":false,"coin":2}
        """#.utf8)

        let relation = try JSONDecoder().decode(VideoRelation.self, from: json)
        XCTAssertTrue(relation.isFollowing)
        XCTAssertTrue(relation.isLiked)
        XCTAssertTrue(relation.isCoined)
        XCTAssertFalse(relation.isFavorited)
        XCTAssertFalse(relation.isDisliked)
    }

    func testVideoTagsDecode() throws {
        let json = Data(#"[{"tag_id":1,"tag_name":"自杀俱乐部"},{"tag_id":2,"tag_name":"日恐"}]"#.utf8)
        let tags = try JSONDecoder().decode([VideoTag].self, from: json)
        XCTAssertEqual(tags.map(\.tagName), ["自杀俱乐部", "日恐"])
    }

    /// 带 rid 查询时收藏夹会多返回 fav_state，收藏夹弹窗靠它决定默认勾选。
    func testFavFolderDecodesFavState() throws {
        let json = Data(#"""
        {"count":2,"list":[
        {"id":1,"title":"默认收藏夹","media_count":10,"fav_state":1},
        {"id":2,"title":"稍后看看","media_count":3,"fav_state":0}]}
        """#.utf8)

        let payload = try JSONDecoder().decode(FavFolderList.self, from: json)
        let folders = try XCTUnwrap(payload.list)
        XCTAssertTrue(folders[0].containsQueriedVideo)
        XCTAssertFalse(folders[1].containsQueriedVideo)
    }

    /// 不带 rid 查询时没有 fav_state，不能因此解码失败——收藏页就是这么用的。
    func testFavFolderWithoutFavStateStillDecodes() throws {
        let json = Data(#"{"count":1,"list":[{"id":1,"title":"默认收藏夹","media_count":10}]}"#.utf8)
        let payload = try JSONDecoder().decode(FavFolderList.self, from: json)
        XCTAssertEqual(try XCTUnwrap(payload.list).first?.containsQueriedVideo, false)
    }

    /// 三连是三步分别判定的：硬币不够时只有投币那步为 false。
    func testTripleResultDecodesPartialSuccess() throws {
        let json = Data(#"{"like":true,"coin":false,"fav":true,"multiply":0}"#.utf8)
        let result = try JSONDecoder().decode(TripleResult.self, from: json)
        XCTAssertTrue(result.didLike)
        XCTAssertFalse(result.didCoin)
        XCTAssertTrue(result.didFavorite)
    }

    /// 评论的 `action` 字段是「我有没有赞过」。老响应里没有这个字段时不能解码失败。
    func testCommentDecodesLikeState() throws {
        let liked = Data(#"""
        {"rpid":1,"ctime":1700000000,"like":5,"rcount":0,"action":1,
        "member":{"uname":"a","avatar":"x"},"content":{"message":"m"}}
        """#.utf8)
        XCTAssertTrue(try JSONDecoder().decode(Comment.self, from: liked).isLikedByServer)

        let missing = Data(#"""
        {"rpid":2,"ctime":1700000000,"like":0,"rcount":0,
        "member":{"uname":"a","avatar":"x"},"content":{"message":"m"}}
        """#.utf8)
        XCTAssertFalse(try JSONDecoder().decode(Comment.self, from: missing).isLikedByServer)
    }

    /// 下拉刷新被 SwiftUI 取消时抛的是取消错误，不能当成加载失败弹给用户。
    func testCancellationErrorsAreRecognised() {
        XCTAssertTrue(CancellationError().isCancellation)
        XCTAssertTrue(URLError(.cancelled).isCancellation)
        XCTAssertFalse(URLError(.timedOut).isCancellation)
        XCTAssertFalse(BiliAPIError.riskControlled.isCancellation)
    }

    /// 删除历史要的 kid 是「业务名_条目号」，传裸数字接口会回 -400。
    func testHistoryKidUsesBusinessPrefix() throws {
        let json = Data(#"""
        {"title":"t","kid":114514,
        "history":{"business":"archive","oid":114514,"bvid":"BV1","cid":2,"type":3}}
        """#.utf8)
        let item = try JSONDecoder().decode(HistoryItem.self, from: json)
        XCTAssertEqual(item.kidParam, "archive_114514")
    }

    /// 条目上没有 kid 时退回用 oid，前缀仍然是业务名。
    func testHistoryKidFallsBackToOid() throws {
        let json = Data(#"""
        {"title":"t","history":{"business":"archive","oid":222,"bvid":"BV1","cid":2,"type":3}}
        """#.utf8)
        let item = try JSONDecoder().decode(HistoryItem.self, from: json)
        XCTAssertEqual(item.kidParam, "archive_222")
    }

    // MARK: - 评论表情

    /// 表情表是可选的：没有表情的评论必须照样解码。
    func testCommentDecodesEmoteTable() throws {
        let json = Data(#"""
        {"rpid":1,"ctime":1700000000,"like":0,"rcount":0,
        "member":{"uname":"a","avatar":"x"},
        "content":{"message":"[doge]还真想看看","emote":{
        "[doge]":{"url":"http://i0.hdslb.com/doge.png","meta":{"size":1}},
        "[给心心]":{"url":"http://i0.hdslb.com/heart.png","meta":{"size":2}}}}}
        """#.utf8)

        let comment = try JSONDecoder().decode(Comment.self, from: json)
        XCTAssertEqual(comment.emotes.count, 2)
        // 表情图必须走 https，和其它 B 站图片一致。
        XCTAssertEqual(comment.emotes["[doge]"]?.secureURL?.scheme, "https")
        // 大表情画得比行内小表情高。
        let small = try XCTUnwrap(comment.emotes["[doge]"]).heightMultiplier
        let large = try XCTUnwrap(comment.emotes["[给心心]"]).heightMultiplier
        XCTAssertGreaterThan(large, small)
    }

    func testCommentWithoutEmoteTableStillDecodes() throws {
        let json = Data(#"""
        {"rpid":1,"ctime":1,"like":0,"rcount":0,
        "member":{"uname":"a","avatar":"x"},"content":{"message":"没有表情"}}
        """#.utf8)
        XCTAssertTrue(try JSONDecoder().decode(Comment.self, from: json).emotes.isEmpty)
    }

    // MARK: - 文字大小

    /// 档位数和系统「文字大小」那七个刻度一致，越界要被夹住而不是崩溃。
    func testTextSizeStepsAreClamped() {
        XCTAssertEqual(AppTextSize.steps.count, 7)
        XCTAssertEqual(AppTextSize.size(at: AppTextSize.defaultIndex), .large)
        XCTAssertEqual(AppTextSize.size(at: -5), .xSmall)
        XCTAssertEqual(AppTextSize.size(at: 99), .xxxLarge)
    }
}
