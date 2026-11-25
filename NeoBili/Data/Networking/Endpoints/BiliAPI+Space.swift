import NeoBiliDomain
import Foundation

extension BiliAPI {
    /// UP 主空间页头部要的那一堆信息：头像、头图、签名、等级、大会员，
    /// 以及粉丝 / 关注 / 获赞三个数字和「我有没有关注他」。
    ///
    /// 走的是不需要 WBI 的 `card` 接口——`space/wbi/acc/info` 风控严得多，
    /// 而这里要的字段它基本都有。唯一拿不到的是 IP 属地，那一项直接不显示。
    static func spaceCard(mid: Int, client: APIClient) async throws -> SpaceCard {
        let payload: SpaceCardPayload = try await client.get(
            path: "x/web-interface/card",
            params: ["mid": String(mid), "photo": "true"]
        )
        return payload.asSpaceCard(mid: mid)
    }

    /// 仅完整空间页请求 App 头图；直播关注等名片使用方不增加请求。
    static func spaceProfile(mid: Int, client: APIClient) async throws -> SpaceCard {
        async let profile = spaceCard(mid: mid, client: client)
        async let background: SpaceBackgroundPayload? = try? client.getApp(
            path: "x/v2/space", params: ["vmid": String(mid)], retries: 0
        )
        var card = try await profile
        card.appBackground = await background?.images
        try Task.checkCancellation()
        return card
    }

    /// 空间投稿使用 WBI 签名及旧网页列表的 fingerprintParams；播放取流使用独立上下文。
    static func spaceVideos(mid: Int, page: Int, client: APIClient) async throws -> SpaceVideoPage {
        var params = [
            "mid": String(mid),
            "pn": String(page),
            "ps": "30",
            "index": "1",
            "order": "pubdate",
            "order_avoided": "true",
            "platform": "web",
            "web_location": "1550101"
        ]
        params.merge(fingerprintParams()) { current, _ in current }
        return try await client.get(
            path: "x/space/wbi/arc/search",
            params: params,
            requiresWBI: true,
            additionalHeaders: [
                "Origin": "https://space.bilibili.com",
                "Referer": "https://space.bilibili.com/\(mid)/video"
            ]
        )
    }

    static func spaceCollections(mid: Int, page: Int, client: APIClient) async throws -> SpaceCollectionListPage {
        try await client.get(
            path: "x/polymer/web-space/seasons_series_list",
            params: ["mid": String(mid), "page_num": String(page), "page_size": "20"],
            requiresWBI: true,
            additionalHeaders: spaceListHeaders(mid: mid)
        )
    }

    static func spaceSeasonArchives(mid: Int, seasonID: Int, page: Int, sortReverse: Bool,
                                    client: APIClient) async throws -> SpaceCollectionArchivePage {
        // true 反转合集的默认编排，分集页面会按发布时间排序已加载的稿件。
        try await client.get(
            path: "x/polymer/web-space/seasons_archives_list",
            params: ["mid": String(mid), "season_id": String(seasonID), "page_num": String(page),
                     "page_size": "30", "sort_reverse": sortReverse ? "true" : "false"],
            requiresWBI: true,
            additionalHeaders: spaceListHeaders(mid: mid)
        )
    }

    static func spaceSeriesArchives(mid: Int, seriesID: Int, page: Int, sortReverse: Bool,
                                    client: APIClient) async throws -> SpaceCollectionArchivePage {
        try await client.get(
            path: "x/series/archives",
            params: ["mid": String(mid), "series_id": String(seriesID), "only_normal": "true",
                     "pn": String(page), "ps": "30", "sort": sortReverse ? "desc" : "asc"],
            requiresWBI: true,
            additionalHeaders: spaceListHeaders(mid: mid)
        )
    }

    private static func spaceListHeaders(mid: Int) -> [String: String] {
        ["Origin": "https://space.bilibili.com", "Referer": "https://space.bilibili.com/\(mid)/lists"]
    }
}
