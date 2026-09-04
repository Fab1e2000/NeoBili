import Foundation

// MARK: - 个人信息（x/web-interface/nav）

/// 登录用户信息。nav 对访客也返回 code 0（`isLogin: false` + 空字段），
/// 所以除 `isLogin` 外全部按可选解码，由 `AccountStore` 统一判空。
struct AccountProfilePayload: Decodable, Sendable {
    let isLogin: Bool?
    let mid: Int?
    let uname: String?
    let face: String?
    let money: Double?
    let vipStatus: Int?
    let levelInfo: LevelInfo?

    enum CodingKeys: String, CodingKey {
        case isLogin, mid, uname, face, money
        case vipStatus
        case levelInfo = "level_info"
    }

    struct LevelInfo: Decodable, Sendable {
        let currentLevel: Int?

        enum CodingKeys: String, CodingKey {
            case currentLevel = "current_level"
        }
    }
}

// MARK: - 收藏（x/v3/fav/folder/*）

/// `list-all` 的 data 不是裸数组，而是 `{"count": N, "list": [...]}`。
struct FavFolderList: Decodable, Sendable {
    let count: Int?
    let list: [FavFolder]?
}

/// 账号创建的收藏夹（含默认收藏夹）。`id` 是 media_id，查收藏内容用它。
struct FavFolder: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let mediaCount: Int
    /// 查询时带上 `rid`（稿件 avid）才有这个字段：1 表示这个收藏夹里已经有该视频。
    /// 收藏夹选择弹窗据此决定哪几项默认打勾。
    let favState: Int?

    /// 这个收藏夹当前是否已收藏了所查询的视频。
    var containsQueriedVideo: Bool { favState == 1 }

    enum CodingKeys: String, CodingKey {
        case id, title
        case mediaCount = "media_count"
        case favState = "fav_state"
    }
}

struct FavResourceList: Decodable, Sendable {
    let info: Info?
    let medias: [FavMedia]?

    struct Info: Decodable, Sendable {
        let title: String?
        let mediaCount: Int?

        enum CodingKeys: String, CodingKey {
            case title
            case mediaCount = "media_count"
        }
    }
}

/// 收藏夹里的一条内容。`type == 2` 才是普通视频稿件；课程、合集等其它类型
/// 字段缺失、详情页打不开，统一在列表层过滤掉。
struct FavMedia: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let bvid: String?
    let type: Int?
    let title: String
    let cover: String?
    let duration: Int?
    let cntInfo: CntInfo?
    let upper: Upper?

    enum CodingKeys: String, CodingKey {
        case id, bvid, type, title, cover, duration, upper
        case cntInfo = "cnt_info"
    }

    var isVideo: Bool { type == 2 }

    var asVideoSummary: VideoSummary? {
        guard isVideo, let bvid, !bvid.isEmpty, let upper else { return nil }
        let counts = cntInfo
        return VideoSummary(
            bvid: bvid,
            aid: id,
            // 收藏接口不带 cid；详情页打开后会自己取到，不影响播放。
            cid: 0,
            title: title,
            pic: cover ?? "",
            desc: "",
            duration: duration ?? 0,
            pubdate: 0,
            owner: VideoOwner(mid: upper.mid ?? 0, name: upper.name ?? "", face: upper.face ?? ""),
            stat: VideoStat(
                view: counts?.play ?? 0,
                danmaku: counts?.danmaku ?? 0,
                like: 0,
                favorite: 0,
                coin: 0,
                share: 0,
                reply: 0
            )
        )
    }

    struct CntInfo: Decodable, Hashable, Sendable {
        let play: Int?
        let danmaku: Int?
    }

    struct Upper: Decodable, Hashable, Sendable {
        let mid: Int?
        let name: String?
        let face: String?
    }
}

// MARK: - 历史（x/web-interface/history/cursor）

struct HistoryCursorPage: Decodable, Sendable {
    /// 大坑：文档写的是 `items`，实际接口返回的键名是 `list`
    /// （PiliPlus 也是按 `list` 解析的）。两个键都解，谁在用谁。
    let items: [HistoryItem]?
    let list: [HistoryItem]?
    let cursor: Cursor?

    var allItems: [HistoryItem] { items ?? list ?? [] }

    struct Cursor: Decodable, Sendable {
        /// 下一页游标；-1 表示没有更多内容。
        let max: Int?
        private let viewAt: Int?
        private let maxViewAt: Int?

        enum CodingKeys: String, CodingKey {
            case max
            case viewAt = "view_at"
            case maxViewAt = "max_view_at"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            max = try container.decodeIfPresent(Int.self, forKey: .max)
            // 文档里是 view_at；max_view_at 兼容个别版本的字段名。
            viewAt = try container.decodeIfPresent(Int.self, forKey: .viewAt)
            maxViewAt = try container.decodeIfPresent(Int.self, forKey: .maxViewAt)
        }

        var resolvedViewAt: Int? { viewAt ?? maxViewAt }
    }
}

/// 一条观看历史。真正的视频定位信息在 `history` 节点里。
struct HistoryItem: Decodable, Identifiable, Hashable, Sendable {
    let title: String
    let longTitle: String?
    let cover: String?
    let duration: Int?
    let authorName: String?
    let viewAt: Int?
    let progress: Int?
    let history: HistoryNode
    /// 接口在条目上直接给出 kid（archive 类型就是 aid），删除时优先用它。
    let kid: Int?

    enum CodingKeys: String, CodingKey {
        case title
        case longTitle = "long_title"
        case cover, duration
        case authorName = "author_name"
        case viewAt = "view_at"
        case progress, history, kid
    }

    struct HistoryNode: Decodable, Hashable, Sendable {
        let business: String?
        let oid: Int?
        let bvid: String?
        let cid: Int?
        let type: Int?
    }

    var id: String { "\(history.business ?? "?")-\(history.oid ?? 0)" }

    /// 有的条目 title 是「已清空的稿件」之类的占位文本，真正标题在 long_title。
    var displayTitle: String {
        let fallback = longTitle ?? ""
        return title.isEmpty ? fallback : title
    }

    /// 只展示普通视频稿件（business == "archive"）；直播/专栏等打不开详情页。
    var isVideo: Bool { history.business == "archive" && history.bvid?.isEmpty == false }

    /// 删除单条历史用的 kid 字符串：优先用接口直接给的值，
    /// 缺失时按 `<type>_<oid>` 自行拼接（archive 的 type 是 3）。
    /// 删除历史时要传的 kid。
    ///
    /// 格式是「业务名_条目号」，例如 `archive_114514`——普通视频的业务名就是
    /// `archive`。之前传的是裸数字（或者拿 `type` 当前缀），接口一律回 -400。
    var kidParam: String {
        let business = history.business ?? "archive"
        return "\(business)_\(kid ?? history.oid ?? 0)"
    }

    var asVideoSummary: VideoSummary? {
        guard isVideo, let bvid = history.bvid else { return nil }
        return VideoSummary(
            bvid: bvid,
            aid: history.oid ?? 0,
            cid: history.cid ?? 0,
            title: displayTitle,
            pic: cover ?? "",
            desc: "",
            duration: duration ?? 0,
            pubdate: 0,
            owner: VideoOwner(mid: 0, name: authorName ?? "", face: ""),
            stat: VideoStat(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0)
        )
    }
}

// MARK: - 稍后再看（x/v2/history/toview）

struct WatchLaterPage: Decodable, Sendable {
    let count: Int?
    let list: [WatchLaterItem]?
}

struct WatchLaterItem: Decodable, Identifiable, Hashable, Sendable {
    let aid: Int?
    let bvid: String?
    let cid: Int?
    let title: String
    let pic: String?
    let duration: Int?
    let addAt: Int?
    /// toview/web 变体返回 `owner`（与视频详情一致），老接口是 `upper`，两者都解。
    let upper: Upper?

    enum CodingKeys: String, CodingKey {
        case aid, bvid, cid, title, pic, duration, upper, owner
        case addAt = "add_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        aid = try container.decodeIfPresent(Int.self, forKey: .aid)
        bvid = try container.decodeIfPresent(String.self, forKey: .bvid)
        cid = try container.decodeIfPresent(Int.self, forKey: .cid)
        title = try container.decode(String.self, forKey: .title)
        pic = try container.decodeIfPresent(String.self, forKey: .pic)
        duration = try container.decodeIfPresent(Int.self, forKey: .duration)
        addAt = try container.decodeIfPresent(Int.self, forKey: .addAt)
        if let owner = try container.decodeIfPresent(Upper.self, forKey: .owner) {
            upper = owner
        } else {
            upper = try container.decodeIfPresent(Upper.self, forKey: .upper)
        }
    }

    var id: Int { aid ?? bvid.hashValue }

    var asVideoSummary: VideoSummary? {
        guard let bvid, !bvid.isEmpty else { return nil }
        return VideoSummary(
            bvid: bvid,
            aid: aid ?? 0,
            cid: cid ?? 0,
            title: title,
            pic: pic ?? "",
            desc: "",
            duration: duration ?? 0,
            pubdate: addAt ?? 0,
            owner: VideoOwner(
                mid: upper?.mid ?? 0,
                name: upper?.name ?? "",
                face: upper?.face ?? ""
            ),
            stat: VideoStat(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0)
        )
    }

    struct Upper: Decodable, Hashable, Sendable {
        let mid: Int?
        let name: String?
        let face: String?
    }
}
