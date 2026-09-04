import Foundation

extension Int {
    /// 播放量、点赞数这类大数字的中文写法：1.2万、3.4亿。
    var biliCountText: String {
        if self >= 100_000_000 {
            return String(format: "%.1f亿", Double(self) / 100_000_000)
        }
        if self >= 10_000 {
            return String(format: "%.1f万", Double(self) / 10_000)
        }
        return String(self)
    }

    /// 稿件发布时间（秒级时间戳）的相对写法：刚刚、23分钟前、3小时前、昨天、
    /// 9月4日。关注页的卡片用它，和 B 站客户端动态流的时间行一致。
    var biliRelativeTimeText: String {
        let date = Date(timeIntervalSince1970: TimeInterval(self))
        let elapsed = Date().timeIntervalSince(date)
        if elapsed < 60 { return "刚刚" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))分钟前" }
        if elapsed < 86_400 { return "\(Int(elapsed / 3600))小时前" }

        let calendar = Calendar.current
        if calendar.isDateInYesterday(date) { return "昨天" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        let isThisYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
        formatter.dateFormat = isThisYear ? "M月d日" : "yyyy年M月d日"
        return formatter.string(from: date)
    }

    /// 稿件发布时间（秒级时间戳）的中文写法：2026年9月4日 09:00。
    var biliPubdateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(self)))
    }
}

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
struct VideoSummary: Decodable, Identifiable, Hashable {
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

    var id: String { bvid }

    var secureCoverURL: URL? { URL.biliSecure(pic) }
    var secureAvatarURL: URL? { URL.biliSecure(owner.face) }

    var formattedDuration: String {
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct PopularFeedPage: Decodable {
    let list: [VideoSummary]
    let noMore: Bool
    enum CodingKeys: String, CodingKey {
        case list
        case noMore = "no_more"
    }
}

struct VideoPart: Decodable, Identifiable, Hashable, Sendable {
    let cid: Int
    let page: Int
    let part: String
    let duration: Int
    var id: Int { cid }
}

struct VideoDetail: Decodable, Hashable, Sendable {
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
    /// 分区名（「单机游戏」这类）。
    let tname: String?
    /// 1 是自制，2 是转载。界面上据此显示「未经作者授权禁止转载」。
    let copyright: Int?
    /// 稿件所属的合集。大多数视频没有合集，所以是可选的。
    let ugcSeason: UgcSeason?

    enum CodingKeys: String, CodingKey {
        case bvid, aid, cid, title, desc, pic, duration, pubdate, owner, stat, pages
        case tname, copyright
        case ugcSeason = "ugc_season"
    }

    var secureCoverURL: URL? { URL.biliSecure(pic) }
    var secureAvatarURL: URL? { URL.biliSecure(owner.face) }
}

// MARK: - 合集（ugc_season）

/// UP 主把多个稿件编成的合集。结构是「合集 → 若干 section → 若干 episode」，
/// 绝大多数合集只有一个 section，界面上直接把所有 section 的分集拉平展示。
///
/// 字段一律按可选解码：这块内容对播放不是必需的，某个字段缺失不该让整个
/// 视频详情解析失败、把页面变成错误页。
struct UgcSeason: Decodable, Hashable, Sendable {
    let id: Int?
    let title: String?
    let cover: String?
    let mid: Int?
    let sections: [UgcSeasonSection]?

    /// 拉平后的全部分集，界面只关心这一个列表。
    var episodes: [UgcSeasonEpisode] {
        (sections ?? []).flatMap { $0.episodes ?? [] }
    }
}

struct UgcSeasonSection: Decodable, Hashable, Sendable {
    let id: Int?
    let title: String?
    let episodes: [UgcSeasonEpisode]?
}

struct UgcSeasonEpisode: Decodable, Identifiable, Hashable, Sendable {
    /// 接口里的 `id` 字段。列表 ID 用下面的 `id`，两者不是一回事。
    let episodeId: Int?
    let aid: Int?
    let cid: Int?
    let bvid: String?
    let title: String?
    let arc: UgcSeasonArchive?

    enum CodingKeys: String, CodingKey {
        case episodeId = "id"
        case aid, cid, bvid, title, arc
    }

    var secureCoverURL: URL? { arc?.pic.flatMap { URL.biliSecure($0) } }

    var formattedDuration: String {
        guard let duration = arc?.duration, duration > 0 else { return "" }
        return String(format: "%d:%02d", duration / 60, duration % 60)
    }

    /// 分集本身没有独立 id 时用 bvid 兜底，避免多条记录共用同一个列表 ID。
    var id: String { bvid ?? String(episodeId ?? aid ?? 0) }
}

/// 分集自带的稿件信息，封面和时长都在这里，不需要再逐条请求详情。
struct UgcSeasonArchive: Decodable, Hashable, Sendable {
    let pic: String?
    let duration: Int?
    let stat: UgcSeasonStat?
}

struct UgcSeasonStat: Decodable, Hashable, Sendable {
    let view: Int?
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

// MARK: - Play URL (DASH)

struct DashStream: Decodable, Hashable, Sendable {
    let id: Int
    let baseUrl: String
    let backupUrl: [String]?
    let bandwidth: Int
    let mimeType: String
    let codecs: String
    let width: Int?
    let height: Int?
    let frameRate: String?
}

extension DashStream {
    private enum CodingKeys: String, CodingKey {
        case id, bandwidth, codecs, width, height
        case baseURL = "baseUrl"
        case baseURLSnake = "base_url"
        case backupURL = "backupUrl"
        case backupURLSnake = "backup_url"
        case mimeType = "mimeType"
        case mimeTypeSnake = "mime_type"
        case frameRate, frameRateSnake = "frame_rate"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        baseUrl = try container.decodeIfPresent(String.self, forKey: .baseURLSnake)
            ?? (try container.decode(String.self, forKey: .baseURL))
        backupUrl = try container.decodeIfPresent([String].self, forKey: .backupURLSnake)
            ?? (try container.decodeIfPresent([String].self, forKey: .backupURL))
        bandwidth = try container.decode(Int.self, forKey: .bandwidth)
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeTypeSnake)
            ?? (try container.decode(String.self, forKey: .mimeType))
        codecs = try container.decode(String.self, forKey: .codecs)
        width = try container.decodeIfPresent(Int.self, forKey: .width)
        height = try container.decodeIfPresent(Int.self, forKey: .height)
        frameRate = try container.decodeIfPresent(String.self, forKey: .frameRateSnake)
            ?? (try container.decodeIfPresent(String.self, forKey: .frameRate))
    }
}

struct DashPayload: Decodable, Hashable, Sendable {
    let duration: Int
    let video: [DashStream]
    let audio: [DashStream]
}

/// A legacy "progressive" (already muxed audio+video) stream. Requesting this
/// format instead of DASH keeps MVP playback to a single file URL, with no
/// client-side track merging required.
struct DurlItem: Decodable, Hashable, Sendable {
    let url: String
    let backupUrl: [String]?
    let length: Int?
    let size: Int?
}

extension DurlItem {
    private enum CodingKeys: String, CodingKey {
        case url, length, size
        case backupURL = "backupUrl"
        case backupURLSnake = "backup_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        backupUrl = try container.decodeIfPresent([String].self, forKey: .backupURLSnake)
            ?? (try container.decodeIfPresent([String].self, forKey: .backupURL))
        length = try container.decodeIfPresent(Int.self, forKey: .length)
        size = try container.decodeIfPresent(Int.self, forKey: .size)
    }
}

struct PlayURLData: Decodable, Hashable, Sendable {
    /// 这三个字段界面上并没有用到，而且被风控拦下时接口根本不返回它们。
    /// 设成可选之后，风控响应能正常解码，播放流程就还有机会去试其它格式，
    /// 而不是在第一步就抛出「数据解析失败」。
    let quality: Int?
    let acceptQuality: [Int]?
    let acceptDescription: [String]?
    let durl: [DurlItem]?
    let dash: DashPayload?
    /// 风控挑战。B 站拦下请求时 `code` 仍然是 0，
    /// 但 `data` 里只有这一个字段，没有任何播放地址。
    let vVoucher: String?

    /// 这次返回是被风控拦下的，不是视频本身不支持播放。
    var isRiskControlled: Bool {
        vVoucher != nil && durl == nil && dash == nil
    }

    var hasPlayableStream: Bool {
        durl?.isEmpty == false || dash != nil
    }

    enum CodingKeys: String, CodingKey {
        case quality, dash, durl
        case acceptQuality = "accept_quality"
        case acceptDescription = "accept_description"
        case vVoucher = "v_voucher"
    }
}
