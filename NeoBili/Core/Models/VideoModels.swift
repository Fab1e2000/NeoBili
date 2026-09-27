import Foundation

struct VideoOwner: Decodable, Hashable, Sendable {
    let mid: Int
    let name: String
    let face: String
}

struct VideoStat: Decodable, Hashable, Sendable {
    let view: Int
    let danmaku: Int
    let like: Int
    let favorite: Int
    let coin: Int
    let share: Int
    let reply: Int
}

/// A single entry in a video feed (popular / recommend lists).
struct VideoSummary: Decodable, Identifiable, Hashable, VideoDimensionProviding {
    let bvid: String
    let aid: Int
    let cid: Int
    let title: String
    let pic: String
    let desc: String
    let duration: Int
    let pubdate: Int
    let owner: VideoOwner
    let stat: VideoStat

    /// 部分列表接口会直接返回画面尺寸；缺失时由内容过滤服务补查详情。
    var dimension: VideoDimension? = nil

    /// App 推荐卡片的「不感兴趣」选项，反馈时原样带回卡片的 goto 和 param。
    var recommendationFeedback: RecommendationFeedbackOptions? = nil
    /// 来自网页推荐：没有原因可选，「不感兴趣」和 PiliPlus 一样只能点踩。
    var isWebRecommendation = false
    /// 推荐卡上 UP 主名字前的小标签，如「已关注」「4万点赞」，和 PiliPlus 一样。
    var recommendationBadge: String? = nil
    /// 推荐流里的直播、图文卡借用视频卡片的外观，点开时去直播间或动态详情，不是视频。
    /// 它们的 `bvid` 是 `live-房间号`、`dynamic-动态编号` 这样的本地标识，只用来区分卡片。
    var recommendationTarget: RecommendationTarget? = nil

    var id: String { bvid }

    var secureCoverURL: URL? { URL.biliSecure(pic) }
    var secureAvatarURL: URL? { URL.biliSecure(owner.face) }

    /// 封面右下角的文字：视频是时长，直播卡是「直播」。
    var coverCornerText: String {
        if case .live = recommendationTarget { return String(localized: "直播") }
        return recommendationTarget == nil ? formattedDuration : ""
    }

    var formattedDuration: String {
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

enum RecommendationTarget: Decodable, Hashable, Sendable {
    case live(LiveRoom)
    /// 图文动态的编号，点开时再取详情。
    case dynamic(id: String)
}

/// App 推荐卡片 `three_point_v2` 里的两组原因：「我不想看」与「反馈」。
struct RecommendationFeedbackOptions: Decodable, Hashable, Sendable {
    struct Reason: Decodable, Hashable, Sendable {
        let id: Int
        let name: String?
        let toast: String?
    }

    /// 反馈接口要求原样带回卡片的 `card_goto` 与 `param`。
    let goto: String
    let param: Int
    var dislikeReasons: [Reason]?
    var feedbacks: [Reason]?

    var hasReasons: Bool { dislikeReasons != nil || feedbacks != nil }
}

struct VideoPart: Decodable, Identifiable, Hashable, Sendable {
    let cid: Int
    let page: Int
    let part: String
    let duration: Int
    /// 各分P可能采用不同画幅，不能一直沿用稿件第一P的尺寸。
    var dimension: VideoDimension? = nil
    var id: Int { cid }

    var formattedDuration: String {
        guard duration > 0 else { return "" }
        let hours = duration / 3600
        let minutes = (duration % 3600) / 60
        let seconds = duration % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct VideoDetail: Decodable, Hashable, Sendable, VideoDimensionProviding {
    let bvid: String
    let aid: Int
    let cid: Int
    let title: String
    let desc: String
    let pic: String
    let duration: Int
    let pubdate: Int
    let owner: VideoOwner
    let stat: VideoStat
    let pages: [VideoPart]
    var dimension: VideoDimension? = nil
    /// 分区名（「单机游戏」这类）。
    let tname: String?
    /// 1 是自制，2 是转载。界面上据此显示「未经作者授权禁止转载」。
    let copyright: Int?
    /// 稿件所属的合集。大多数视频没有合集，所以是可选的。
    let ugcSeason: UgcSeason?

    enum CodingKeys: String, CodingKey {
        case bvid, aid, cid, title, desc, pic, duration, pubdate, owner, stat, pages, dimension
        case tname, copyright
        case ugcSeason = "ugc_season"
    }

    var secureCoverURL: URL? { URL.biliSecure(pic) }
    var secureAvatarURL: URL? { URL.biliSecure(owner.face) }
}

// MARK: - 标签、互动状态、UP 主名片

/// 稿件标签，展示在简介的操作栏上方。
struct VideoTag: Decodable, Identifiable, Hashable, Sendable {
    let tagId: Int
    let tagName: String

    var id: Int { tagId }

    enum CodingKeys: String, CodingKey {
        case tagId = "tag_id"
        case tagName = "tag_name"
    }
}

/// 当前账号和这个稿件之间的关系：点赞、投币、收藏、点踩，以及是否关注了 UP 主。
/// 一次请求把五个按钮的高亮状态全拿回来，不必逐个接口去问。
///
/// 未登录时接口仍返回 code 0，但所有布尔值都是 false、`coin` 是 0。
struct VideoRelation: Decodable, Hashable, Sendable {
    /// 是否已关注 UP 主。
    let attention: Bool?
    let favorite: Bool?
    let like: Bool?
    let dislike: Bool?
    /// 已投的硬币数，不是布尔值。
    let coin: Int?

    var isLiked: Bool { like == true }
    var isDisliked: Bool { dislike == true }
    var isFavorited: Bool { favorite == true }
    var isCoined: Bool { (coin ?? 0) > 0 }
    var isFollowing: Bool { attention == true }
}

/// 一键三连的结果。三步是分别判定的：硬币不够时 `coin` 为 false，
/// 但点赞和收藏照样成功，所以界面要按字段分别更新，不能一把当成全成功。
struct TripleResult: Decodable, Hashable, Sendable {
    let like: Bool?
    let coin: Bool?
    let fav: Bool?
    /// 实际投出去的硬币数。
    let multiply: Int?

    var didLike: Bool { like == true }
    var didCoin: Bool { coin == true }
    var didFavorite: Bool { fav == true }
}

/// UP 主名片，用来显示「X 万粉丝 · N 视频」。
struct MemberCard: Decodable, Hashable, Sendable {
    let follower: Int?
    let archiveCount: Int?

    enum CodingKeys: String, CodingKey {
        case follower
        case archiveCount = "archive_count"
    }
}
