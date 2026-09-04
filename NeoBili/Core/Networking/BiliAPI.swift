import Foundation

/// Endpoint-level calls, kept separate from the transport (`APIClient`) so
/// feature view models only ever talk to this facade.
enum BiliAPI {
    static func popularVideos(page: Int) async throws -> PopularFeedPage {
        try await APIClient.shared.get(
            path: "x/web-interface/popular",
            params: ["pn": String(page), "ps": "20"]
        )
    }

    /// The web recommendation feed used by PiliPlus. Unlike the fixed daily
    /// popular ranking, advancing `fresh_idx` yields a new recommendation batch.
    static func recommendFeed(freshIndex: Int) async throws -> [VideoSummary] {
        let page: RecommendFeedPage = try await APIClient.shared.get(
            path: "x/web-interface/wbi/index/top/feed/rcmd",
            params: [
                "version": "1",
                "fresh_type": "4",
                "feed_version": "V8",
                "homepage_ver": "1",
                "ps": "20",
                "fresh_idx": String(freshIndex),
                "brush": String(freshIndex)
            ],
            requiresWBI: true
        )
        return page.item.compactMap { $0.asVideoSummary }
    }

    static func videoDetail(bvid: String) async throws -> VideoDetail {
        try await APIClient.shared.get(
            path: "x/web-interface/view",
            params: ["bvid": bvid]
        )
    }

    /// 官方「相关视频」推流，只跟当前这个视频有关。
    ///
    /// 这和首页的推荐流是两个完全不同的接口：首页用的是 `top/feed/rcmd`，
    /// 按用户整体兴趣出内容；这里用的是 `archive/related`，由 B 站根据当前稿件
    /// 算出关联稿件。返回的卡片结构和推荐流一致，而且自带 `cid`，
    /// 所以点进去时可以和推荐页一样并行加载详情与播放地址。
    static func relatedVideos(bvid: String) async throws -> [VideoSummary] {
        let items: [RelatedVideoItem] = try await APIClient.shared.get(
            path: "x/web-interface/archive/related",
            params: ["bvid": bvid]
        )
        return items.compactMap(\.asVideoSummary)
    }

    /// 视频评论。
    ///
    /// `oid` 要传 av 号（`aid`）而不是 bvid，`type: 1` 表示这是视频稿件的评论区。
    /// `sort: 1` 是按点赞数排序，也就是网页端默认的「热门」。
    /// 每条一级评论会顺带返回最多 3 条楼中楼，展示它们不需要再发请求。
    static func comments(aid: Int, page: Int) async throws -> CommentPage {
        try await APIClient.shared.get(
            path: "x/v2/reply",
            params: [
                "type": "1",
                "oid": String(aid),
                "pn": String(page),
                "ps": "20",
                "sort": "1"
            ]
        )
    }

    /// 展开某条评论下的全部回复（楼中楼）。`root` 传那条一级评论的 `rpid`。
    ///
    /// 和一级评论不同，这个接口对未登录用户没有条数限制，可以正常一页页翻。
    static func commentReplies(aid: Int, rootId: Int, page: Int) async throws -> CommentReplyPage {
        try await APIClient.shared.get(
            path: "x/v2/reply/reply",
            params: [
                "type": "1",
                "oid": String(aid),
                "root": String(rootId),
                "pn": String(page),
                "ps": "20"
            ],
            requiresWBI: true
        )
    }

    static func searchVideos(keyword: String, page: Int) async throws -> SearchResultPage {
        let response: SearchResultPage = try await APIClient.shared.get(
            path: "x/web-interface/wbi/search/type",
            params: SearchRequest.parameters(keyword: keyword, page: page),
            requiresWBI: true,
            additionalHeaders: SearchRequest.headers(keyword: keyword)
        )
        // 搜索风控与取流接口一样会返回 code=0，但 data 里只有挑战串。
        // 不能把这种响应解码成“没有搜索结果”，否则用户只会看到空页面。
        guard response.vVoucher == nil else {
            throw BiliAPIError.riskControlled
        }
        // video 分类里仍可能混入课堂推广卡，它们没有 bvid，不能进入普通
        // 视频详情页；同时过滤后可避免多个空字符串破坏 SwiftUI 的列表 ID。
        return SearchResultPage(result: response.result?.filter { !$0.bvid.isEmpty }, vVoucher: nil)
    }

    // MARK: - 账号（登录后）

    /// 当前登录用户的个人信息。nav 对访客返回 code 0 但 `isLogin == false`，
    /// Cookie 失效时返回 -101，由 `AccountStore` 据此清理本地凭据。
    static func myProfile() async throws -> AccountProfilePayload {
        try await APIClient.shared.get(path: "x/web-interface/nav")
    }

    /// 自己创建的收藏夹列表（含默认收藏夹）。
    /// `list-all` 的 data 是 `{"count": N, "list": [...]}`，不是裸数组。
    ///
    /// 传了 `videoAid` 时每个收藏夹会多带一个 `fav_state`，表示它里面有没有
    /// 这个视频——收藏夹选择弹窗靠它决定默认勾选哪几项，不必逐个收藏夹去查。
    static func favoriteFolders(ownerMid: Int, videoAid: Int? = nil) async throws -> [FavFolder] {
        var params = ["up_mid": String(ownerMid)]
        if let videoAid {
            params["type"] = "2"
            params["rid"] = String(videoAid)
        }
        let payload: FavFolderList = try await APIClient.shared.get(
            path: "x/v3/fav/folder/created/list-all",
            params: params
        )
        return payload.list ?? []
    }

    static func favoriteVideos(folderID: Int, page: Int) async throws -> FavResourceList {
        try await APIClient.shared.get(
            path: "x/v3/fav/resource/list",
            params: [
                "media_id": String(folderID),
                "pn": String(page),
                "ps": "20",
                "order": "mtime",
                "platform": "web"
            ]
        )
    }

    /// 从某个收藏夹里取消收藏。
    ///
    /// 走的就是下面那个 `updateFavorites`——`deal` 接口只认 `add_media_ids` 和
    /// `del_media_ids` 两个字段。这里以前写的是 `remove_media_ids`，服务端认不出
    /// 来，于是每次都返回成功却什么也没删，表现就是「取消收藏没反应」。
    static func removeFavorite(folderID: Int, aid: Int) async throws {
        try await updateFavorites(aid: aid, addFolderIDs: [], removeFolderIDs: [folderID])
    }

    /// 把稿件从**所有**收藏夹里移除。收藏按钮在已收藏状态下再点一次走这里。
    static func unfavoriteEverywhere(aid: Int) async throws {
        let csrf = await DeviceIdentity.shared.csrfToken ?? ""
        try await APIClient.shared.post(
            path: "x/v3/fav/resource/unfav-all",
            form: ["rid": String(aid), "type": "2", "csrf": csrf]
        )
    }

    /// 删除整个收藏夹。可以一次删多个，服务端要求逗号分隔。
    static func deleteFavoriteFolders(folderIDs: [Int]) async throws {
        let csrf = await DeviceIdentity.shared.csrfToken ?? ""
        try await APIClient.shared.post(
            path: "x/v3/fav/folder/del",
            form: [
                "media_ids": folderIDs.map(String.init).joined(separator: ","),
                "platform": "web",
                "csrf": csrf
            ]
        )
    }

    /// 加入稍后再看。avid 和 bvid 给一个就行——搜索结果只有 bvid。
    static func addWatchLater(aid: Int?, bvid: String?) async throws {
        let csrf = await DeviceIdentity.shared.csrfToken ?? ""
        var form = ["csrf": csrf]
        if let aid { form["aid"] = String(aid) }
        if let bvid { form["bvid"] = bvid }
        try await APIClient.shared.post(path: "x/v2/history/toview/add", form: form)
    }

    /// 观看历史按游标翻页：首页 max=0 / view_at=0，之后带上上一页返回的游标。
    static func historyPage(max: Int, viewAt: Int) async throws -> HistoryCursorPage {
        try await APIClient.shared.get(
            path: "x/web-interface/history/cursor",
            params: [
                "type": "archive",
                "ps": "20",
                "max": String(max),
                "view_at": String(viewAt)
            ]
        )
    }

    /// 删除单条观看历史。
    ///
    /// 端点是 `x/v2/history/delete`——之前写成了 `x/web-interface/history/del`，
    /// 那个路径根本不存在，所以返回的是 HTTP 404 而不是业务错误码。
    static func deleteHistory(kid: String) async throws {
        let csrf = await DeviceIdentity.shared.csrfToken ?? ""
        try await APIClient.shared.post(
            path: "x/v2/history/delete",
            form: ["kid": kid, "jsonp": "jsonp", "csrf": csrf]
        )
    }

    static func watchLaterList() async throws -> WatchLaterPage {
        try await APIClient.shared.get(path: "x/v2/history/toview")
    }

    /// 移出稍后再看。
    static func removeWatchLater(aid: Int) async throws {
        let csrf = await DeviceIdentity.shared.csrfToken ?? ""
        try await APIClient.shared.post(
            path: "x/v2/history/toview/del",
            form: ["aid": String(aid), "csrf": csrf]
        )
    }

    // MARK: - 视频页附加信息

    /// 稿件标签。这是网页端播放页现在用的那个端点，不是更早的 `x/tag/archive/tags`。
    static func videoTags(aid: Int) async throws -> [VideoTag] {
        try await APIClient.shared.get(
            path: "x/web-interface/view/detail/tag",
            params: ["aid": String(aid)]
        )
    }

    /// 当前账号与这个稿件的关系：点赞、投币、收藏、点踩、是否关注 UP 主。
    ///
    /// 五个按钮的高亮状态一次拿全。未登录时接口照样返回 code 0，只是全为假值，
    /// 所以调用方不需要为访客单独分支。
    static func videoRelation(aid: Int, bvid: String) async throws -> VideoRelation {
        try await APIClient.shared.get(
            path: "x/web-interface/archive/relation",
            params: ["aid": String(aid), "bvid": bvid]
        )
    }

    /// UP 主名片，用来显示粉丝数和投稿数。`photo=false` 让服务端不必附带空间头图。
    static func memberCard(mid: Int) async throws -> MemberCard {
        let payload: MemberCardPayload = try await APIClient.shared.get(
            path: "x/web-interface/card",
            params: ["mid": String(mid), "photo": "false"]
        )
        return MemberCard(follower: payload.follower, archiveCount: payload.archiveCount)
    }

    // MARK: - 视频页写操作（登录后）

    /// 点赞 / 取消点赞。`like` 传 true 是点赞，false 是取消。
    static func likeVideo(aid: Int, like: Bool) async throws {
        let csrf = await DeviceIdentity.shared.csrfToken ?? ""
        try await APIClient.shared.post(
            path: "x/web-interface/archive/like",
            form: [
                "aid": String(aid),
                "like": like ? "1" : "2",
                "csrf": csrf
            ]
        )
    }

    /// 点踩 / 取消点踩。
    ///
    /// 网页端没有这个写接口，只能走 App 端，因此它需要 `access_key`——也就是
    /// 只有扫码登录的账号能用（见 `APIClient.postApp`）。密码登录的账号调用时
    /// 会拿到 `BiliAPIError.missingAccessKey`。
    static func dislikeVideo(aid: Int, dislike: Bool) async throws {
        try await APIClient.shared.postApp(
            path: "x/v2/view/dislike",
            form: [
                "aid": String(aid),
                // 注意这个接口是反的：0 才是点踩，1 是取消点踩。传反了服务端会回
                // 65005「取消踩失败，未点踩过」，看起来像点踩功能整个不能用。
                "dislike": dislike ? "0" : "1"
            ]
        )
    }

    /// 一键三连：点赞 + 投币 + 收藏到默认收藏夹，服务端一次做完。
    ///
    /// 返回值说明这三步各自的结果——账号硬币不够时 `coin` 会是 false，
    /// 但点赞和收藏仍然成功，所以要按字段分别反映到界面上。
    static func tripleAction(aid: Int) async throws -> TripleResult {
        let csrf = await DeviceIdentity.shared.csrfToken ?? ""
        return try await APIClient.shared.post(
            path: "x/web-interface/archive/like/triple",
            form: ["aid": String(aid), "csrf": csrf]
        )
    }

    /// 给评论点赞 / 取消点赞。`oid` 传视频的 avid，`type: 1` 表示视频稿件的评论区。
    static func likeComment(aid: Int, rpid: Int, like: Bool) async throws {
        let csrf = await DeviceIdentity.shared.csrfToken ?? ""
        try await APIClient.shared.post(
            path: "x/v2/reply/action",
            form: [
                "type": "1",
                "oid": String(aid),
                "rpid": String(rpid),
                "action": like ? "1" : "0",
                "csrf": csrf
            ]
        )
    }

    /// 投币。`multiply` 上限是 2；`selectLike` 为 true 时顺带点赞。
    static func addCoin(aid: Int, multiply: Int, selectLike: Bool = false) async throws {
        let csrf = await DeviceIdentity.shared.csrfToken ?? ""
        try await APIClient.shared.post(
            path: "x/web-interface/coin/add",
            form: [
                "aid": String(aid),
                "multiply": String(multiply),
                "select_like": selectLike ? "1" : "0",
                "csrf": csrf
            ]
        )
    }

    /// 一次性调整这个视频在各个收藏夹里的归属。
    /// 两个列表都可以为空，服务端按「加入这些、移出那些」处理。
    static func updateFavorites(aid: Int, addFolderIDs: [Int], removeFolderIDs: [Int]) async throws {
        let csrf = await DeviceIdentity.shared.csrfToken ?? ""
        try await APIClient.shared.post(
            path: "x/v3/fav/resource/deal",
            form: [
                "rid": String(aid),
                "type": "2",
                "add_media_ids": addFolderIDs.map(String.init).joined(separator: ","),
                "del_media_ids": removeFolderIDs.map(String.init).joined(separator: ","),
                "csrf": csrf
            ]
        )
    }

    /// 关注 / 取消关注 UP 主。
    ///
    /// 这个接口会校验来源站点，所以要把 Origin/Referer 换成 space 站——沿用
    /// 全站默认的 www 来源会被拒。`re_src=11` 表示来源是视频播放页。
    static func modifyRelation(mid: Int, follow: Bool) async throws {
        let csrf = await DeviceIdentity.shared.csrfToken ?? ""
        try await APIClient.shared.post(
            path: "x/relation/modify",
            form: [
                "fid": String(mid),
                "act": follow ? "1" : "2",
                "re_src": "11",
                "gaia_source": "web_main",
                "spmid": "333.788",
                "csrf": csrf
            ],
            additionalHeaders: [
                "Origin": "https://space.bilibili.com",
                "Referer": "https://space.bilibili.com/\(mid)/dynamic"
            ]
        )
    }

    /// Requests a DASH-first play manifest for `bvid`/`cid`.
    ///
    /// mpv 能直接打开 DASH 拆开的视频、音频两条流（靠 `edl://` 伪协议拼成一个
    /// 输入，见 `PlaybackSourceBuilder.edlURL`），不需要像 AVFoundation 那样
    /// 先探测再拼 composition，所以 DASH 和 durl 对首帧速度没有区别——直接
    /// 按编码能力和画质优先选 DASH，durl 只在稿件不提供 DASH 时才用到。
    static func playURL(bvid: String, cid: Int) async throws -> PlayURLData {
        let formats: [[String: String]] = [
            ["qn": "64", "fnval": "4048", "fnver": "0", "fourk": "0", "otype": "json", "platform": "pc"],
            // 某些稿件的网页端参数不接受 4048，仍请求完整 DASH 能力集。
            ["qn": "64", "fnval": "16", "fnver": "0", "fourk": "0", "otype": "json", "platform": "pc"],
            // 最后的兼容路径：服务端已经合并好的文件。
            ["qn": "64", "fnval": "1", "fnver": "0", "otype": "json", "platform": "html5", "high_quality": "1"]
        ]

        var wasRiskControlled = false
        for extraParams in formats {
            do {
                let payload = try await requestPlayURL(bvid: bvid, cid: cid, extraParams: extraParams)
                if payload.isRiskControlled {
                    // 风控是针对这次请求的，换个格式仍有可能被放行，所以继续往下试。
                    wasRiskControlled = true
                    continue
                }
                if payload.hasPlayableStream {
                    return payload
                }
            } catch {
                // code -400 在这个接口中表示当前参数或流格式不适用。
                // 只有这种情况才换格式重试；断网、超时等错误仍立即显示。
                guard Self.isUnsupportedPlayFormat(error) else { throw error }
            }
        }

        // 三种格式都被拦下时要说清楚是风控，不能报成「该视频不支持播放」误导用户。
        if wasRiskControlled {
            throw BiliAPIError.riskControlled
        }
        throw BiliAPIError.apiError(code: -1, message: "该视频暂不支持播放")
    }

    private static func requestPlayURL(
        bvid: String,
        cid: Int,
        extraParams: [String: String]
    ) async throws -> PlayURLData {
        var params = extraParams
        params["bvid"] = bvid
        params["cid"] = String(cid)
        params.merge(riskControlParams()) { current, _ in current }
        return try await APIClient.shared.get(
            path: "x/player/wbi/playurl",
            params: params,
            requiresWBI: true
        )
    }

    /// 绕开 B 站风控（内部代号 Gaia）所需的参数，取自 PiliPlus 的实现。
    ///
    /// 不带这些参数时，取流请求会被拦下：`code` 仍然是 0，但 `data` 里只有一个
    /// `v_voucher` 挑战串，没有任何播放地址。实测同一批视频，裸参数全部被拦，
    /// 补上这组参数后全部正常返回。
    ///
    /// `gaia_source` 和 `isGaiaAvoided` 直接对应风控系统；三个 `dm_` 字段是网页
    /// 播放器上报的浏览器指纹，网页端每次都会带上随机值，缺了就不像真实浏览器。
    private static func riskControlParams() -> [String: String] {
        [
            "gaia_source": "pre-load",
            "isGaiaAvoided": "true",
            "web_location": "1315873",
            // 未登录也能拿到较高画质。
            "try_look": "1",
            "voice_balance": "0",
            "dm_img_list": "[]",
            "dm_img_str": randomFingerprint(minimumBytes: 16, maximumBytes: 64),
            "dm_cover_img_str": randomFingerprint(minimumBytes: 32, maximumBytes: 128),
            "dm_img_inter": #"{"ds":[],"wh":[0,0,0],"of":[0,0,0]}"#
        ]
    }

    /// 网页播放器上报的是一段 WebGL 采样数据，长度不固定。
    /// 我们没有那份数据，用等长的随机串代替即可，服务端只看格式。
    private static func randomFingerprint(minimumBytes: Int, maximumBytes: Int) -> String {
        let count = Int.random(in: minimumBytes...maximumBytes)
        let bytes = (0..<count).map { _ in UInt8.random(in: .min ... .max) }
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
    }

    private static func isUnsupportedPlayFormat(_ error: Error) -> Bool {
        guard let biliError = error as? BiliAPIError,
              case .apiError(let code, _) = biliError
        else { return false }
        return code == -400
    }
}

/// `x/web-interface/card` 的 data 里除了名片本体，粉丝数和投稿数是平铺在
/// 顶层的（`follower` / `archive_count`），所以单独解一层再收敛成 `MemberCard`。
private struct MemberCardPayload: Decodable {
    let follower: Int?
    let archiveCount: Int?

    enum CodingKeys: String, CodingKey {
        case follower
        case archiveCount = "archive_count"
    }
}

/// 相关视频列表里偶尔混有番剧等条目，字段不一定齐全。
/// 和推荐流一样先宽松解码，再过滤成能正常展示的普通视频，
/// 避免其中一条异常数据让整个列表解析失败。
private struct RelatedVideoItem: Decodable {
    let bvid: String?
    let aid: Int?
    let cid: Int?
    let title: String?
    let pic: String?
    let desc: String?
    let duration: Int?
    let pubdate: Int?
    let owner: VideoOwner?
    let stat: RelatedVideoStat?

    var asVideoSummary: VideoSummary? {
        guard let bvid, let aid, let cid, let title, let pic,
              let duration, let pubdate, let owner, let stat
        else { return nil }
        return VideoSummary(
            bvid: bvid, aid: aid, cid: cid, title: title, pic: pic,
            desc: desc ?? "", duration: duration, pubdate: pubdate,
            owner: owner,
            stat: VideoStat(
                view: stat.view ?? 0,
                danmaku: stat.danmaku ?? 0,
                like: stat.like ?? 0,
                favorite: stat.favorite ?? 0,
                coin: stat.coin ?? 0,
                share: stat.share ?? 0,
                reply: stat.reply ?? 0
            )
        )
    }
}

private struct RelatedVideoStat: Decodable {
    let view: Int?
    let danmaku: Int?
    let like: Int?
    let favorite: Int?
    let coin: Int?
    let share: Int?
    let reply: Int?
}

/// `top/rcmd` mixes video cards with ads/live/bangumi entries (`goto != "av"`)
/// and doesn't guarantee every field a plain video has, so this decodes
/// leniently and `asVideoSummary` filters down to what we can actually show.
private struct RecommendFeedItem: Decodable {
    let goto: String?
    let bvid: String?
    let aid: Int?
    let cid: Int?
    let title: String?
    let pic: String?
    let desc: String?
    let duration: Int?
    let pubdate: Int?
    let owner: VideoOwner?
    let stat: RecommendFeedStat?

    enum CodingKeys: String, CodingKey {
        case goto, bvid, cid, title, pic, desc, duration, pubdate, owner, stat
        case aid = "id"
    }

    var asVideoSummary: VideoSummary? {
        guard goto == "av",
              let bvid, let aid, let cid, let title, let pic,
              let duration, let pubdate, let owner, let stat
        else { return nil }
        return VideoSummary(
            bvid: bvid, aid: aid, cid: cid, title: title, pic: pic,
            desc: desc ?? "", duration: duration, pubdate: pubdate,
            owner: owner,
            stat: VideoStat(
                view: stat.view ?? 0,
                danmaku: stat.danmaku ?? 0,
                like: stat.like ?? 0,
                favorite: 0,
                coin: 0,
                share: 0,
                reply: 0
            )
        )
    }
}

/// Recommendation cards intentionally contain only the counters needed by
/// the feed. Decoding them as a full `VideoStat` makes otherwise-valid feed
/// responses fail because fields such as `favorite` and `coin` are absent.
private struct RecommendFeedStat: Decodable {
    let view: Int?
    let danmaku: Int?
    let like: Int?
}

private struct RecommendFeedPage: Decodable {
    let item: [RecommendFeedItem]
}

struct SearchResultItem: Decodable, Identifiable, Hashable {
    let bvid: String
    let title: String
    let author: String
    let pic: String
    let duration: String
    let play: Int

    var id: String { bvid }

    /// Search results wrap the matched keyword in `<em>` tags; strip them for display.
    var plainTitle: String {
        title.replacingOccurrences(of: "<em class=\"keyword\">", with: "")
             .replacingOccurrences(of: "</em>", with: "")
    }

    var secureCoverURL: URL? { URL.biliSecure(pic) }
}

struct SearchResultPage: Decodable {
    let result: [SearchResultItem]?
    let vVoucher: String?

    enum CodingKeys: String, CodingKey {
        case result
        case vVoucher = "v_voucher"
    }
}

/// B 站搜索接口会同时检查 WBI 参数、页面位置和来源站点。这里集中生成请求，
/// 避免以后改搜索分页时漏掉其中一项又落入 Gaia 风控。
enum SearchRequest {
    static func parameters(keyword: String, page: Int) -> [String: String] {
        [
            "keyword": keyword,
            "page": String(page),
            "page_size": "20",
            "platform": "pc",
            "search_type": "video",
            "web_location": "1430654"
        ]
    }

    static func headers(keyword: String) -> [String: String] {
        var components = URLComponents(string: "https://search.bilibili.com/video")!
        components.queryItems = [URLQueryItem(name: "keyword", value: keyword)]
        return [
            "Origin": "https://search.bilibili.com",
            "Referer": components.url?.absoluteString ?? "https://search.bilibili.com/video"
        ]
    }
}
