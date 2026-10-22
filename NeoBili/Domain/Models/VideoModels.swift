import Foundation

public struct VideoOwner: Decodable, Hashable, Sendable {
    public let mid: Int
    public let name: String
    public let face: String

    public init(
        mid: Int,
        name: String,
        face: String
    ) {
        self.mid = mid
        self.name = name
        self.face = face
    }
}

public struct VideoStat: Decodable, Hashable, Sendable {
    public let view: Int
    public let danmaku: Int
    public let like: Int
    public let favorite: Int
    public let coin: Int
    public let share: Int
    public let reply: Int

    public init(
        view: Int,
        danmaku: Int,
        like: Int,
        favorite: Int,
        coin: Int,
        share: Int,
        reply: Int
    ) {
        self.view = view
        self.danmaku = danmaku
        self.like = like
        self.favorite = favorite
        self.coin = coin
        self.share = share
        self.reply = reply
    }
}

/// A single entry in a video feed (popular / recommend lists).
public struct VideoSummary: Decodable, Identifiable, Hashable, VideoDimensionProviding, Sendable {
    public let bvid: String
    public let aid: Int
    public let cid: Int
    public let title: String
    public let pic: String
    public let desc: String
    public let duration: Int
    public let pubdate: Int
    public let owner: VideoOwner
    public let stat: VideoStat

    /// 部分列表接口会直接返回画面尺寸；缺失时由内容过滤服务补查详情。
    public var dimension: VideoDimension? = nil

    /// App 推荐卡片的「不感兴趣」选项，反馈时原样带回卡片的 goto 和 param。
    public var recommendationFeedback: RecommendationFeedbackOptions? = nil
    public var playbackEntry: PlaybackEntry = .other
    /// Original feed fields for an actual card click, never reconstructed from playback.
    public var recommendationClickFields: [String: String]? = nil
    public var recommendationPosition: Int? = nil
    /// Retains the server's full-width video presentation through local filters.
    public var isLargeRecommendationCard = false
    /// 来自网页推荐：没有原因可选，「不感兴趣」和 PiliPlus 一样只能点踩。
    public var isWebRecommendation = false
    /// 推荐卡上 UP 主名字前的小标签，如「已关注」「4万点赞」，和 PiliPlus 一样。
    public var recommendationBadge: String? = nil
    /// 推荐流里的直播、图文卡借用视频卡片的外观，点开时去直播间或动态详情，不是视频。
    /// 它们的 `bvid` 是 `live-房间号`、`dynamic-动态编号` 这样的本地标识，只用来区分卡片。
    public var recommendationTarget: RecommendationTarget? = nil

    public var id: String { bvid }

    public var secureCoverURL: URL? { URL.biliSecure(pic) }
    public var secureAvatarURL: URL? { URL.biliSecure(owner.face) }

    /// 封面右下角的文字：视频是时长，直播卡是「直播」。
    public var coverCornerText: String {
        if case .live = recommendationTarget { return String(localized: "直播") }
        return recommendationTarget == nil ? formattedDuration : ""
    }

    public var formattedDuration: String {
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    public init(
        bvid: String,
        aid: Int,
        cid: Int,
        title: String,
        pic: String,
        desc: String,
        duration: Int,
        pubdate: Int,
        owner: VideoOwner,
        stat: VideoStat,
        dimension: VideoDimension? = nil,
        recommendationFeedback: RecommendationFeedbackOptions? = nil,
        playbackEntry: PlaybackEntry = .other,
        recommendationClickFields: [String: String]? = nil,
        recommendationPosition: Int? = nil,
        isLargeRecommendationCard: Bool = false,
        isWebRecommendation: Bool = false,
        recommendationBadge: String? = nil,
        recommendationTarget: RecommendationTarget? = nil
    ) {
        self.bvid = bvid
        self.aid = aid
        self.cid = cid
        self.title = title
        self.pic = pic
        self.desc = desc
        self.duration = duration
        self.pubdate = pubdate
        self.owner = owner
        self.stat = stat
        self.dimension = dimension
        self.recommendationFeedback = recommendationFeedback
        self.playbackEntry = playbackEntry
        self.recommendationClickFields = recommendationClickFields
        self.recommendationPosition = recommendationPosition
        self.isLargeRecommendationCard = isLargeRecommendationCard
        self.isWebRecommendation = isWebRecommendation
        self.recommendationBadge = recommendationBadge
        self.recommendationTarget = recommendationTarget
    }
}

extension VideoSummary {
    private enum CodingKeys: String, CodingKey {
        case bvid, aid, cid, title, pic, desc, duration, pubdate, owner, stat, dimension
        case recommendationFeedback, isWebRecommendation, recommendationBadge, recommendationTarget
    }

    /// `isWebRecommendation` is local presentation metadata, absent from normal
    /// video-list responses. A stored Swift default is not a Decodable default.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        bvid = try values.decode(String.self, forKey: .bvid)
        aid = try values.decode(Int.self, forKey: .aid)
        cid = try values.decode(Int.self, forKey: .cid)
        title = try values.decode(String.self, forKey: .title)
        pic = try values.decode(String.self, forKey: .pic)
        desc = try values.decode(String.self, forKey: .desc)
        duration = try values.decode(Int.self, forKey: .duration)
        pubdate = try values.decode(Int.self, forKey: .pubdate)
        owner = try values.decode(VideoOwner.self, forKey: .owner)
        stat = try values.decode(VideoStat.self, forKey: .stat)
        dimension = try values.decodeIfPresent(VideoDimension.self, forKey: .dimension)
        recommendationFeedback = try values.decodeIfPresent(RecommendationFeedbackOptions.self, forKey: .recommendationFeedback)
        isWebRecommendation = try values.decodeIfPresent(Bool.self, forKey: .isWebRecommendation) ?? false
        recommendationBadge = try values.decodeIfPresent(String.self, forKey: .recommendationBadge)
        recommendationTarget = try values.decodeIfPresent(RecommendationTarget.self, forKey: .recommendationTarget)
    }
}

public enum RecommendationTarget: Decodable, Hashable, Sendable {
    case live(LiveRoom)
    /// 图文动态的编号，点开时再取详情。
    case dynamic(id: String)
}

/// App 推荐卡片 `three_point_v2` 里的两组原因：「我不想看」与「反馈」。
public struct RecommendationFeedbackOptions: Decodable, Hashable, Sendable {
    public struct Reason: Decodable, Hashable, Sendable {
        public let id: Int
        public let name: String?
        public let toast: String?

        public init(
            id: Int,
            name: String? = nil,
            toast: String? = nil
        ) {
            self.id = id
            self.name = name
            self.toast = toast
        }
    }

    /// 反馈接口要求原样带回卡片的 `card_goto` 与 `param`。
    public let goto: String
    public let param: Int
    public var dislikeReasons: [Reason]?
    public var feedbacks: [Reason]?
    /// Bound when the card is received, not when a later account taps its menu.
    public var requestContext: RequestContext? = nil

    public struct RequestContext: Decodable, Hashable, Sendable {
        public let loginSessionID: UUID
        public let parameters: [String: String]

        public init(
            loginSessionID: UUID,
            parameters: [String: String]
        ) {
            self.loginSessionID = loginSessionID
            self.parameters = parameters
        }
    }

    public var hasReasons: Bool { dislikeReasons != nil || feedbacks != nil }

    public init(
        goto: String,
        param: Int,
        dislikeReasons: [Reason]? = nil,
        feedbacks: [Reason]? = nil,
        requestContext: RequestContext? = nil
    ) {
        self.goto = goto
        self.param = param
        self.dislikeReasons = dislikeReasons
        self.feedbacks = feedbacks
        self.requestContext = requestContext
    }
}

public struct VideoPart: Decodable, Identifiable, Hashable, Sendable {
    public let cid: Int
    public let page: Int
    public let part: String
    public let duration: Int
    /// 各分P可能采用不同画幅，不能一直沿用稿件第一P的尺寸。
    public var dimension: VideoDimension? = nil
    public var id: Int { cid }

    public var formattedDuration: String {
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

public struct VideoDetail: Decodable, Hashable, Sendable, VideoDimensionProviding {
    public let bvid: String
    public let aid: Int
    public let cid: Int
    public let title: String
    public let desc: String
    public let pic: String
    public let duration: Int
    public let pubdate: Int
    public let owner: VideoOwner
    public let stat: VideoStat
    public let pages: [VideoPart]
    public var dimension: VideoDimension? = nil
    /// 分区名（「单机游戏」这类）。
    public let tname: String?
    /// 1 是自制，2 是转载。界面上据此显示「未经作者授权禁止转载」。
    public let copyright: Int?
    /// 稿件所属的合集。大多数视频没有合集，所以是可选的。
    public let ugcSeason: UgcSeason?

    enum CodingKeys: String, CodingKey {
        case bvid, aid, cid, title, desc, pic, duration, pubdate, owner, stat, pages, dimension
        case tname, copyright
        case ugcSeason = "ugc_season"
    }

    public var secureCoverURL: URL? { URL.biliSecure(pic) }
    public var secureAvatarURL: URL? { URL.biliSecure(owner.face) }
}

// MARK: - 标签、互动状态、UP 主名片

/// 稿件标签，展示在简介的操作栏上方。
public struct VideoTag: Decodable, Identifiable, Hashable, Sendable {
    public let tagId: Int
    public let tagName: String

    public var id: Int { tagId }

    enum CodingKeys: String, CodingKey {
        case tagId = "tag_id"
        case tagName = "tag_name"
    }
}

/// 当前账号和这个稿件之间的关系：点赞、投币、收藏、点踩，以及是否关注了 UP 主。
/// 一次请求把五个按钮的高亮状态全拿回来，不必逐个接口去问。
///
/// 未登录时接口仍返回 code 0，但所有布尔值都是 false、`coin` 是 0。
public struct VideoRelation: Decodable, Hashable, Sendable {
    /// 是否已关注 UP 主。
    public let attention: Bool?
    public let favorite: Bool?
    public let like: Bool?
    public let dislike: Bool?
    /// 已投的硬币数，不是布尔值。
    public let coin: Int?

    public var isLiked: Bool { like == true }
    public var isDisliked: Bool { dislike == true }
    public var isFavorited: Bool { favorite == true }
    public var isCoined: Bool { (coin ?? 0) > 0 }
    public var isFollowing: Bool { attention == true }

    public init(
        attention: Bool? = nil,
        favorite: Bool? = nil,
        like: Bool? = nil,
        dislike: Bool? = nil,
        coin: Int? = nil
    ) {
        self.attention = attention
        self.favorite = favorite
        self.like = like
        self.dislike = dislike
        self.coin = coin
    }
}

/// 一键三连的结果。三步是分别判定的：硬币不够时 `coin` 为 false，
/// 但点赞和收藏照样成功，所以界面要按字段分别更新，不能一把当成全成功。
public struct TripleResult: Decodable, Hashable, Sendable {
    public let like: Bool?
    public let coin: Bool?
    public let fav: Bool?
    /// 实际投出去的硬币数。
    public let multiply: Int?

    public var didLike: Bool { like == true }
    public var didCoin: Bool { coin == true }
    public var didFavorite: Bool { fav == true }
}

/// UP 主名片，用来显示「X 万粉丝 · N 视频」。
public struct MemberCard: Decodable, Hashable, Sendable {
    public let follower: Int?
    public let archiveCount: Int?

    enum CodingKeys: String, CodingKey {
        case follower
        case archiveCount = "archive_count"
    }

    public init(
        follower: Int? = nil,
        archiveCount: Int? = nil
    ) {
        self.follower = follower
        self.archiveCount = archiveCount
    }
}

/// 来源由实际入口指定。未知入口不伪装成推荐点击；追踪值只来自当前卡片。
public struct PlaybackEntry: Hashable, Sendable {
    public enum Source: String, Sendable {
        case recommendation, related, history, search, favorites, watchLater
        case following, dynamicDetail, spaceVideo, spaceDynamic, collection, other
    }
    public let source: Source
    public var trackID: String? = nil
    public var reportFlowData: String? = nil
    public var loginSessionID: UUID? = nil
    public static let other = Self(source: .other)
    public static let history = Self(source: .history)
    public static let search = Self(source: .search)
    public static let favorites = Self(source: .favorites)
    public static let watchLater = Self(source: .watchLater)
    public static let following = Self(source: .following)
    public static let dynamicDetail = Self(source: .dynamicDetail)
    public static let spaceVideo = Self(source: .spaceVideo)
    public static let spaceDynamic = Self(source: .spaceDynamic)
    public static let collection = Self(source: .collection)
    public static let related = Self(source: .related)
    public static func recommendation(trackID: String?, reportFlowData: String?) -> Self {
        Self(source: .recommendation, trackID: trackID, reportFlowData: reportFlowData)
    }
    public func parameters(for sessionID: UUID? = nil) -> [String: String] {
        var result: [String: String] = [:]
        switch source {
        case .recommendation: result["from"] = "7"; result["from_spmid"] = "tm.recommend.0.0"
        case .related: result["from"] = "2"; result["from_spmid"] = "united.player-video-detail.relatedvideo.0"
        case .history: result["from"] = "64"; result["from_spmid"] = "main.my-history.0.0"
        case .search: result["from"] = "3"; result["from_spmid"] = "search.search-result.0.0"
        case .favorites: result["from"] = "6"; result["from_spmid"] = "main.my-fav.0.0"
        case .watchLater: result["from"] = "6"; result["from_spmid"] = "main.later-watch.0.0"
        case .spaceVideo: result["from"] = "66"; result["from_spmid"] = "main.space-contribution.0.0"
        case .following: result["from"] = "6"; result["from_spmid"] = "dt.dt.video.0"
        // Preserve the real local entry without inventing official wire constants.
        case .dynamicDetail, .spaceDynamic, .collection, .other: break
        }
        let permitsTracking = loginSessionID == nil || loginSessionID == sessionID
        if permitsTracking, let trackID, !trackID.isEmpty { result["track_id"] = trackID }
        if permitsTracking, let reportFlowData, !reportFlowData.isEmpty { result["report_flow_data"] = reportFlowData }
        return result
    }

    public init(
        source: Source,
        trackID: String? = nil,
        reportFlowData: String? = nil,
        loginSessionID: UUID? = nil
    ) {
        self.source = source
        self.trackID = trackID
        self.reportFlowData = reportFlowData
        self.loginSessionID = loginSessionID
    }
}
