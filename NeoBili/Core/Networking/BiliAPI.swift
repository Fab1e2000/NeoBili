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
