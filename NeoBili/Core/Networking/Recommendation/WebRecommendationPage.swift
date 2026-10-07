import Foundation

/// 网页推荐接口的一页，规则照 PiliPlus `VideoHttp.rcmdVideoList`：
/// 只留普通视频（直播、广告等 `goto` 不是 av 的都去掉），再按推荐流设置做本地过滤。
struct WebRecommendationPage: Decodable {
    let cards: [WebRecommendationCard]
    private enum Keys: String, CodingKey { case item }

    init(from decoder: Decoder) throws {
        var items = try decoder.container(keyedBy: Keys.self).nestedUnkeyedContainer(forKey: .item)
        var result: [WebRecommendationCard] = []
        while !items.isAtEnd {
            let decoder = try items.superDecoder()
            if let card = try? WebRecommendationCard(from: decoder) { result.append(card) }
        }
        cards = result
    }

    /// 网页卡片没有分区名，分区关键词过滤不作用于这里（PiliPlus 相同）。
    func videos(filter: RecommendationFilter) -> [VideoSummary] {
        cards.filter { card in
            !filter.dropsOwner(card.video.owner.mid)
                && !filter.drops(duration: card.video.duration, view: card.view ?? -1, like: card.like,
                          title: card.video.title, isFollowed: card.isFollowed)
        }
        .map(\.video)
    }

    static func parameters(freshIndex: Int) -> [String: String] {
        ["version": "1", "feed_version": "V8", "homepage_ver": "1", "ps": "20",
         "fresh_idx": String(freshIndex), "brush": String(freshIndex), "fresh_type": "4"]
    }
}

struct WebRecommendationCard: Decodable {
    let video: VideoSummary
    /// 接口没给的计数保持为空，和 PiliPlus 一样不参与对应的过滤。
    let view: Int?
    let like: Int?
    let isFollowed: Bool

    private struct Skipped: Error {}
    private struct Stat: Decodable {
        let view: Int?
        let danmaku: Int?
        let like: Int?
    }
    private struct Reason: Decodable { let content: String? }
    private enum Key: String, CodingKey {
        case goto, bvid, cid, title, pic, desc, duration, pubdate, owner, stat, dimension
        case aid = "id", isFollowed = "is_followed", rcmdReason = "rcmd_reason"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        guard (try? c.decode(String.self, forKey: .goto)) == "av",
              let owner = try? c.decode(VideoOwner.self, forKey: .owner),
              let aid = try? c.decode(Int.self, forKey: .aid), aid > 0,
              let bvid = try? c.decode(String.self, forKey: .bvid), !bvid.isEmpty,
              let title = try? c.decode(String.self, forKey: .title), !title.isEmpty,
              let pic = try? c.decode(String.self, forKey: .pic), !pic.isEmpty else { throw Skipped() }
        // 缺 cid 的卡照 PiliPlus 保留，点开时由视频页查；这里记 0。
        let cid = max(0, (try? c.decode(Int.self, forKey: .cid)) ?? 0)
        let stat = try? c.decode(Stat.self, forKey: .stat)
        view = stat?.view
        like = stat?.like
        isFollowed = (try? c.decode(Int.self, forKey: .isFollowed)) == 1
        var video = VideoSummary(
            bvid: bvid, aid: aid, cid: cid, title: title, pic: pic,
            desc: (try? c.decode(String.self, forKey: .desc)) ?? "",
            duration: max(0, (try? c.decode(Int.self, forKey: .duration)) ?? 0),
            pubdate: (try? c.decode(Int.self, forKey: .pubdate)) ?? 0,
            owner: owner,
            stat: VideoStat(view: stat?.view ?? 0, danmaku: stat?.danmaku ?? 0, like: stat?.like ?? 0,
                            favorite: 0, coin: 0, share: 0, reply: 0),
            dimension: try? c.decodeIfPresent(VideoDimension.self, forKey: .dimension)
        )
        video.isWebRecommendation = true
        // PiliPlus 分别显示推荐理由和「已关注」两个标签，这里合成一个。
        let reason = (try? c.decode(Reason.self, forKey: .rcmdReason))?.content.flatMap { $0.isEmpty ? nil : $0 }
        var badges = reason.map { [$0] } ?? []
        let followed = String(localized: "已关注")
        if isFollowed, !badges.contains(followed) { badges.append(followed) }
        video.recommendationBadge = badges.isEmpty ? nil : badges.joined(separator: " · ")
        self.video = video
    }
}
