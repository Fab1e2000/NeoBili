import Foundation

// MARK: - UP 主投稿列表（x/space/wbi/arc/search）

struct SpaceVideoPage: Decodable, Sendable {
    let list: List?
    let page: Page?

    var videos: [SpaceVideo] { list?.vlist ?? [] }

    /// 这一页之后还有没有内容。`count` 是投稿总数。
    func hasMore(after loadedCount: Int) -> Bool {
        guard let total = page?.count else { return false }
        return loadedCount < total
    }

    struct List: Decodable, Sendable {
        let vlist: [SpaceVideo]?

        enum CodingKeys: String, CodingKey {
            case vlist
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            vlist = (try? container.decodeIfPresent(LenientList<SpaceVideo>.self, forKey: .vlist))??.elements
        }
    }

    struct Page: Decodable, Sendable {
        let count: Int?
        let pn: Int?
        let ps: Int?

        enum CodingKeys: String, CodingKey {
            case count, pn, ps
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            count = container.flexibleInt(forKey: .count)
            pn = container.flexibleInt(forKey: .pn)
            ps = container.flexibleInt(forKey: .ps)
        }
    }
}

/// 空间投稿列表里的一条视频。时长是 `12:34` 这样的字符串，播放量是裸数字。
struct SpaceVideo: Decodable, Identifiable, Hashable, Sendable, VideoDimensionProviding {
    let aid: Int
    let bvid: String
    let title: String
    let pic: String
    let length: String
    let play: Int
    let author: String
    let mid: Int
    let created: Int
    let dimension: VideoDimension?

    var id: String { bvid }

    enum CodingKeys: String, CodingKey {
        case aid, bvid, title, pic, length, play, author, mid, created, dimension
    }

    init(from decoder: Decoder) throws {
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

    func asFollowedVideo(avatar: String) -> FollowedVideo {
        FollowedVideo(
            id: bvid,
            bvid: bvid,
            aid: aid,
            title: title,
            cover: pic,
            durationText: length,
            playText: play > 0 ? play.biliCountText : "",
            authorMid: mid,
            authorName: author,
            authorFace: avatar,
            publishedText: created > 0 ? created.biliRelativeTimeText : "",
            dimension: dimension
        )
    }
}

// MARK: - UP 主名片（x/web-interface/card）

/// UP 主空间页头部要显示的东西。
struct SpaceCard: Hashable, Sendable {
    let mid: Int
    let name: String
    let face: String
    let sign: String
    let level: Int
    let isVIP: Bool
    /// 空间页顶上那张头图。没设置过的账号会是 B 站的默认图。
    let banner: String?
    let follower: Int
    let followingCount: Int
    let likeCount: Int
    let archiveCount: Int
    /// 当前账号有没有关注他。未登录时恒为 false。
    let isFollowing: Bool

    var secureAvatarURL: URL? { URL.biliSecure(face) }
    var secureBannerURL: URL? { banner.flatMap { URL.biliSecure($0) } }
}

struct SpaceCardPayload: Decodable, Sendable {
    let card: Card?
    /// 头图在这个接口里出现过两个位置：`data.space` 和 `data.card.space`。
    /// 只解其中一个的话，另一种响应就没有头图可显示。
    let space: Card.Space?
    let following: Bool?
    let follower: Int?
    let likeNum: Int?
    let archiveCount: Int?

    enum CodingKeys: String, CodingKey {
        case card, space, following, follower
        case likeNum = "like_num"
        case archiveCount = "archive_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        card = try? container.decodeIfPresent(Card.self, forKey: .card)
        space = try? container.decodeIfPresent(Card.Space.self, forKey: .space)
        following = container.flexibleBool(forKey: .following)
        follower = container.flexibleInt(forKey: .follower)
        likeNum = container.flexibleInt(forKey: .likeNum)
        archiveCount = container.flexibleInt(forKey: .archiveCount)
    }

    func asSpaceCard(mid: Int) -> SpaceCard {
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

    struct Card: Decodable, Sendable {
        let name: String?
        let face: String?
        let sign: String?
        let fans: Int?
        let attention: Int?
        let levelInfo: LevelInfo?
        let vip: Vip?
        let space: Space?

        enum CodingKeys: String, CodingKey {
            case name, face, sign, fans, attention, vip, space
            case levelInfo = "level_info"
        }

        init(from decoder: Decoder) throws {
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

        struct LevelInfo: Decodable, Sendable {
            let currentLevel: Int?

            enum CodingKeys: String, CodingKey {
                case currentLevel = "current_level"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                currentLevel = container.flexibleInt(forKey: .currentLevel)
            }
        }

        struct Vip: Decodable, Sendable {
            let status: Int?

            enum CodingKeys: String, CodingKey { case status }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                status = container.flexibleInt(forKey: .status)
            }
        }

        struct Space: Decodable, Sendable {
            /// 大图，也就是空间页顶部那张头图。
            let largeImage: String?

            enum CodingKeys: String, CodingKey {
                case largeImage = "l_img"
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                largeImage = container.flexibleString(forKey: .largeImage)
            }
        }
    }
}
