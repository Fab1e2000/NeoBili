import Foundation

// MARK: - UP 主投稿列表（x/space/wbi/arc/search）

public struct SpaceVideoPage: Decodable, Sendable {
    public let list: List?
    public let page: Page?

    public var videos: [SpaceVideo] { list?.vlist ?? [] }

    /// 这一页之后还有没有内容。`count` 是投稿总数。
    public func hasMore(after loadedCount: Int) -> Bool {
        guard let total = page?.count else { return false }
        return loadedCount < total
    }

    public struct List: Decodable, Sendable {
        public let vlist: [SpaceVideo]?

        enum CodingKeys: String, CodingKey {
            case vlist
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            vlist = (try? container.decodeIfPresent(LenientList<SpaceVideo>.self, forKey: .vlist))??.elements
        }
    }

    public struct Page: Decodable, Sendable {
        public let count: Int?
        public let pn: Int?
        public let ps: Int?

        enum CodingKeys: String, CodingKey {
            case count, pn, ps
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            count = container.flexibleInt(forKey: .count)
            pn = container.flexibleInt(forKey: .pn)
            ps = container.flexibleInt(forKey: .ps)
        }
    }
}

/// 空间投稿列表里的一条视频。时长是 `12:34` 这样的字符串，播放量是裸数字。
public struct SpaceVideo: Decodable, Identifiable, Hashable, Sendable, VideoDimensionProviding {
    public let aid: Int
    public let bvid: String
    public let title: String
    public let pic: String
    public let length: String
    public let play: Int
    public let author: String
    public let mid: Int
    public let created: Int
    public let dimension: VideoDimension?

    public var id: String { bvid }

    enum CodingKeys: String, CodingKey {
        case aid, bvid, title, pic, length, play, author, mid, created, dimension
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        aid = container.flexibleInt(forKey: .aid) ?? 0
        bvid = container.flexibleString(forKey: .bvid) ?? ""
        title = container.flexibleString(forKey: .title) ?? ""
        pic = container.flexibleString(forKey: .pic) ?? ""
        length = container.flexibleString(forKey: .length) ?? ""
        // 隐藏播放量的稿件这里会返回 `--`，不是数字。
        play = container.flexibleInt(forKey: .play) ?? 0
        author = container.flexibleString(forKey: .author) ?? ""
        mid = container.flexibleInt(forKey: .mid) ?? 0
        created = container.flexibleInt(forKey: .created) ?? 0
        dimension = try? container.decodeIfPresent(VideoDimension.self, forKey: .dimension)
    }
}

// MARK: - UP 主名片（x/web-interface/card）

/// UP 主空间页头部要显示的东西。
public struct SpaceCard: Hashable, Sendable {
    public let mid: Int
    public let name: String
    public let face: String
    public let sign: String
    public let level: Int
    public let isVIP: Bool
    /// 空间页顶上那张头图。没设置过的账号会是 B 站的默认图。
    public let banner: String?
    public let follower: Int
    public let followingCount: Int
    public let likeCount: Int
    public let archiveCount: Int
    /// 当前账号有没有关注他。未登录时恒为 false。
    public let isFollowing: Bool

    public var appBackground: SpaceBackgroundPayload.Images? = nil

    public func bannerURL(isDark: Bool) -> URL? {
        appBackground?.url(isDark: isDark) ?? secureBannerURL
    }

    public var secureAvatarURL: URL? { URL.biliSecure(face) }
    public var secureBannerURL: URL? { banner.flatMap { URL.biliSecure($0) } }
}

public struct SpaceCardPayload: Decodable, Sendable {
    public let card: Card?
    /// 头图在这个接口里出现过两个位置：`data.space` 和 `data.card.space`。
    /// 只解其中一个的话，另一种响应就没有头图可显示。
    public let space: Card.Space?
    public let following: Bool?
    public let follower: Int?
    public let likeNum: Int?
    public let archiveCount: Int?

    enum CodingKeys: String, CodingKey {
        case card, space, following, follower
        case likeNum = "like_num"
        case archiveCount = "archive_count"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        card = try? container.decodeIfPresent(Card.self, forKey: .card)
        space = try? container.decodeIfPresent(Card.Space.self, forKey: .space)
        following = container.flexibleBool(forKey: .following)
        follower = container.flexibleInt(forKey: .follower)
        likeNum = container.flexibleInt(forKey: .likeNum)
        archiveCount = container.flexibleInt(forKey: .archiveCount)
    }

    public func asSpaceCard(mid: Int) -> SpaceCard {
        SpaceCard(
            mid: mid,
            name: card?.name ?? "",
            face: card?.face ?? "",
            sign: card?.sign ?? "",
            level: card?.levelInfo?.currentLevel ?? 0,
            isVIP: (card?.vip?.status ?? 0) == 1,
            banner: card?.space?.largeImage ?? space?.largeImage,
            follower: follower ?? card?.fans ?? 0,
            followingCount: card?.attention ?? 0,
            likeCount: likeNum ?? 0,
            archiveCount: archiveCount ?? 0,
            isFollowing: following ?? false
        )
    }

    public struct Card: Decodable, Sendable {
        public let name: String?
        public let face: String?
        public let sign: String?
        public let fans: Int?
        public let attention: Int?
        public let levelInfo: LevelInfo?
        public let vip: Vip?
        public let space: Space?

        enum CodingKeys: String, CodingKey {
            case name, face, sign, fans, attention, vip, space
            case levelInfo = "level_info"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = container.flexibleString(forKey: .name)
            face = container.flexibleString(forKey: .face)
            sign = container.flexibleString(forKey: .sign)
            fans = container.flexibleInt(forKey: .fans)
            attention = container.flexibleInt(forKey: .attention)
            levelInfo = try? container.decodeIfPresent(LevelInfo.self, forKey: .levelInfo)
            vip = try? container.decodeIfPresent(Vip.self, forKey: .vip)
            space = try? container.decodeIfPresent(Space.self, forKey: .space)
        }

        public struct LevelInfo: Decodable, Sendable {
            public let currentLevel: Int?

            enum CodingKeys: String, CodingKey {
                case currentLevel = "current_level"
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                currentLevel = container.flexibleInt(forKey: .currentLevel)
            }
        }

        public struct Vip: Decodable, Sendable {
            public let status: Int?

            enum CodingKeys: String, CodingKey { case status }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                status = container.flexibleInt(forKey: .status)
            }
        }

        public struct Space: Decodable, Sendable {
            /// 大图，也就是空间页顶部那张头图。
            public let largeImage: String?

            enum CodingKeys: String, CodingKey {
                case largeImage = "l_img"
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                largeImage = container.flexibleString(forKey: .largeImage)
            }
        }
    }
}

/// App 空间响应只读取静态头图，不加载 images 中的装扮或播放资源。
public struct SpaceBackgroundPayload: Decodable, Sendable {
    public let images: Images?

    public struct Images: Decodable, Hashable, Sendable {
        public let imgUrl: String?
        public let night_imgurl: String?

        public func url(isDark: Bool) -> URL? {
            if isDark, let night = Self.imageURL(night_imgurl) { return night }
            return Self.imageURL(imgUrl)
        }

        private static func imageURL(_ raw: String?) -> URL? {
            guard let raw, let url = URL.biliSecure(raw),
                  url.scheme == "https", let host = url.host, !host.isEmpty else { return nil }
            return url
        }
    }
}
