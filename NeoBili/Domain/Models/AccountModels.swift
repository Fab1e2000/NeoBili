import Foundation

// MARK: - 个人信息（x/web-interface/nav）

/// 登录用户信息。nav 对访客也返回 code 0（`isLogin: false` + 空字段），
/// 所以除 `isLogin` 外全部按可选解码，由 `AccountStore` 统一判空。
public struct AccountProfilePayload: Decodable, Sendable {
    public let isLogin: Bool?
    public let mid: Int?
    public let uname: String?
    public let face: String?
    public let money: Double?
    public let vipStatus: Int?
    public let levelInfo: LevelInfo?

    enum CodingKeys: String, CodingKey {
        case isLogin, mid, uname, face, money
        case vipStatus
        case levelInfo = "level_info"
    }

    public struct LevelInfo: Decodable, Sendable {
        public let currentLevel: Int?

        enum CodingKeys: String, CodingKey {
            case currentLevel = "current_level"
        }
    }
}

// MARK: - 收藏（x/v3/fav/folder/*）

/// `list-all` 的 data 不是裸数组，而是 `{"count": N, "list": [...]}`。
public struct FavFolderList: Decodable, Sendable {
    public let count: Int?
    public let list: [FavFolder]?
}

/// 账号创建的收藏夹（含默认收藏夹）。`id` 是 media_id，查收藏内容用它。
public struct FavFolder: Decodable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let title: String
    public let mediaCount: Int
    /// 查询时带上 `rid`（稿件 avid）才有这个字段：1 表示这个收藏夹里已经有该视频。
    /// 收藏夹选择弹窗据此决定哪几项默认打勾。
    public let favState: Int?

    /// 这个收藏夹当前是否已收藏了所查询的视频。
    public var containsQueriedVideo: Bool { favState == 1 }

    enum CodingKeys: String, CodingKey {
        case id, title
        case mediaCount = "media_count"
        case favState = "fav_state"
    }
}

public struct FavResourceList: Decodable, Sendable {
    public let info: Info?
    public let medias: [FavMedia]?

    public struct Info: Decodable, Sendable {
        public let title: String?
        public let mediaCount: Int?

        enum CodingKeys: String, CodingKey {
            case title
            case mediaCount = "media_count"
        }
    }
}

/// 收藏夹里的一条内容。`type == 2` 才是普通视频稿件；课程、合集等其它类型
/// 字段缺失、详情页打不开，统一在列表层过滤掉。
public struct FavMedia: Decodable, Identifiable, Hashable, Sendable, VideoDimensionProviding {
    public let id: Int
    public let bvid: String?
    public let type: Int?
    public let title: String
    public let cover: String?
    public let duration: Int?
    public let cntInfo: CntInfo?
    public let upper: Upper?
    public var dimension: VideoDimension? = nil

    enum CodingKeys: String, CodingKey {
        case id, bvid, type, title, cover, duration, upper, dimension
        case cntInfo = "cnt_info"
    }

    public var isVideo: Bool { type == 2 }

    public var asVideoSummary: VideoSummary? {
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
            ),
            dimension: dimension
        )
    }

    public struct CntInfo: Decodable, Hashable, Sendable {
        public let play: Int?
        public let danmaku: Int?
    }

    public struct Upper: Decodable, Hashable, Sendable {
        public let mid: Int?
        public let name: String?
        public let face: String?
    }
}

// MARK: - 历史（x/web-interface/history/cursor）

public struct HistoryCursorPage: Decodable, Sendable {
    /// 大坑：文档写的是 `items`，实际接口返回的键名是 `list`
    /// （PiliPlus 也是按 `list` 解析的）。两个键都解，谁在用谁。
    public let items: [HistoryItem]?
    public let list: [HistoryItem]?
    public let cursor: Cursor?

    public var allItems: [HistoryItem] { items ?? list ?? [] }

    public struct Cursor: Decodable, Sendable {
        /// 下一页游标；-1 表示没有更多内容。
        public let max: Int?
        private let viewAt: Int?
        private let maxViewAt: Int?

        enum CodingKeys: String, CodingKey {
            case max
            case viewAt = "view_at"
            case maxViewAt = "max_view_at"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            max = try container.decodeIfPresent(Int.self, forKey: .max)
            // 文档里是 view_at；max_view_at 兼容个别版本的字段名。
            viewAt = try container.decodeIfPresent(Int.self, forKey: .viewAt)
            maxViewAt = try container.decodeIfPresent(Int.self, forKey: .maxViewAt)
        }

        public var resolvedViewAt: Int? { viewAt ?? maxViewAt }
    }
}

/// 一条观看历史。真正的视频定位信息在 `history` 节点里。
public struct HistoryItem: Decodable, Identifiable, Hashable, Sendable, VideoDimensionProviding {
    public let title: String
    public let longTitle: String?
    public let cover: String?
    public let duration: Int?
    public let authorName: String?
    public let viewAt: Int?
    public let progress: Int?
    public let history: HistoryNode
    /// 接口在条目上直接给出 kid（archive 类型就是 aid），删除时优先用它。
    public let kid: Int?
    public var dimension: VideoDimension? = nil

    enum CodingKeys: String, CodingKey {
        case title
        case longTitle = "long_title"
        case cover, duration
        case authorName = "author_name"
        case viewAt = "view_at"
        case progress, history, kid, dimension
    }

    public struct HistoryNode: Decodable, Hashable, Sendable {
        public let business: String?
        public let oid: Int?
        public let bvid: String?
        public let cid: Int?
        public let type: Int?
    }

    public var id: String { "\(history.business ?? "?")-\(history.oid ?? 0)" }

    /// 有的条目 title 是「已清空的稿件」之类的占位文本，真正标题在 long_title。
    public var displayTitle: String {
        let fallback = longTitle ?? ""
        return title.isEmpty ? fallback : title
    }

    /// 只展示普通视频稿件（business == "archive"）；直播/专栏等打不开详情页。
    public var isVideo: Bool { history.business == "archive" && history.bvid?.isEmpty == false }

    /// 删除单条历史用的 kid 字符串：优先用接口直接给的值，
    /// 缺失时按 `<type>_<oid>` 自行拼接（archive 的 type 是 3）。
    /// 删除历史时要传的 kid。
    ///
    /// 格式是「业务名_条目号」，例如 `archive_114514`——普通视频的业务名就是
    /// `archive`。之前传的是裸数字（或者拿 `type` 当前缀），接口一律回 -400。
    public var kidParam: String {
        let business = history.business ?? "archive"
        return "\(business)_\(kid ?? history.oid ?? 0)"
    }

    public var asVideoSummary: VideoSummary? {
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
            stat: VideoStat(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0),
            dimension: dimension
        )
    }
}

// MARK: - 稍后再看（x/v2/history/toview）

public struct WatchLaterPage: Decodable, Sendable {
    public let count: Int?
    public let list: [WatchLaterItem]?
}

public struct WatchLaterItem: Decodable, Identifiable, Hashable, Sendable, VideoDimensionProviding {
    public let aid: Int?
    public let bvid: String?
    public let cid: Int?
    public let title: String
    public let pic: String?
    public let duration: Int?
    public let addAt: Int?
    /// toview/web 变体返回 `owner`（与视频详情一致），老接口是 `upper`，两者都解。
    public let upper: Upper?
    public let dimension: VideoDimension?

    enum CodingKeys: String, CodingKey {
        case aid, bvid, cid, title, pic, duration, upper, owner, dimension
        case addAt = "add_at"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        aid = try container.decodeIfPresent(Int.self, forKey: .aid)
        bvid = try container.decodeIfPresent(String.self, forKey: .bvid)
        cid = try container.decodeIfPresent(Int.self, forKey: .cid)
        title = try container.decode(String.self, forKey: .title)
        pic = try container.decodeIfPresent(String.self, forKey: .pic)
        duration = try container.decodeIfPresent(Int.self, forKey: .duration)
        addAt = try container.decodeIfPresent(Int.self, forKey: .addAt)
        dimension = try? container.decodeIfPresent(VideoDimension.self, forKey: .dimension)
        if let owner = try container.decodeIfPresent(Upper.self, forKey: .owner) {
            upper = owner
        } else {
            upper = try container.decodeIfPresent(Upper.self, forKey: .upper)
        }
    }

    public var id: Int { aid ?? bvid.hashValue }

    public var asVideoSummary: VideoSummary? {
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
            stat: VideoStat(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0),
            dimension: dimension
        )
    }

    public struct Upper: Decodable, Hashable, Sendable {
        public let mid: Int?
        public let name: String?
        public let face: String?
    }
}
