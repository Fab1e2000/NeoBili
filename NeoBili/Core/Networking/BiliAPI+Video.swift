import Foundation

extension BiliAPI {
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
    let dimension: VideoDimension?

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
            ),
            dimension: dimension
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
