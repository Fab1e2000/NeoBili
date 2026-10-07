import Foundation

extension BiliAPI {
    /// UP 主空间页头部要的那一堆信息：头像、头图、签名、等级、大会员，
    /// 以及粉丝 / 关注 / 获赞三个数字和「我有没有关注他」。
    ///
    /// 走的是不需要 WBI 的 `card` 接口——`space/wbi/acc/info` 风控严得多，
    /// 而这里要的字段它基本都有。唯一拿不到的是 IP 属地，那一项直接不显示。
    static func spaceCard(mid: Int, client: APIClient = .shared) async throws -> SpaceCard {
        let payload: SpaceCardPayload = try await client.get(
            path: "x/web-interface/card",
            params: ["mid": String(mid), "photo": "true"]
        )
        return payload.asSpaceCard(mid: mid)
    }

    /// 仅完整空间页请求 App 头图；直播关注等名片使用方不增加请求。
    static func spaceProfile(mid: Int, client: APIClient = .shared) async throws -> SpaceCard {
        async let profile = spaceCard(mid: mid, client: client)
        async let background: SpaceBackgroundPayload? = try? client.getApp(
            path: "x/v2/space", params: ["vmid": String(mid)], retries: 0
        )
        var card = try await profile
        card.appBackground = await background?.images
        try Task.checkCancellation()
        return card
    }

    /// 某个 UP 主的投稿列表（空间页「投稿」那一栏）。
    ///
    /// 走 WBI 签名，并且要带上和取流同一组浏览器指纹参数：缺了它们，
    /// 连续翻几页之后就会被风控挡下（-352）。
    static func spaceVideos(mid: Int, page: Int) async throws -> SpaceVideoPage {
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
        return try await APIClient.shared.get(
            path: "x/space/wbi/arc/search",
            params: params,
            requiresWBI: true,
            additionalHeaders: [
                "Origin": "https://space.bilibili.com",
                "Referer": "https://space.bilibili.com/\(mid)/video"
            ]
        )
    }
}
