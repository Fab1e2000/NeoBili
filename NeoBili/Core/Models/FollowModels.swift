import Foundation

// MARK: - 关注页要展示的一条投稿

/// 「关注」页列表里的一条视频。
///
/// 动态接口和空间投稿接口返回的字段名、类型都不一样（动态的播放量是服务端
/// 排好版的「1.2万」，空间接口给的是裸数字），所以两边各自转换成这一个模型，
/// 卡片视图只认识它。
struct FollowedVideo: Identifiable, Hashable, Sendable {
    /// 列表标识。动态流用动态 id（同一个稿件可能被不同动态带出来），
    /// 空间投稿列表用 bvid。
    let id: String
    let bvid: String
    let aid: Int
    let title: String
    let cover: String
    /// 已经排好版的时长，例如 `12:34`。
    let durationText: String
    /// 已经排好版的播放量，例如 `1.2万`。
    let playText: String
    let authorMid: Int
    let authorName: String
    let authorFace: String
    /// 「3小时前」这类相对时间。
    let publishedText: String

    var secureCoverURL: URL? { URL.biliSecure(cover) }
    var secureAvatarURL: URL? { URL.biliSecure(authorFace) }
}

// MARK: - 关注的 UP 主（x/polymer/web-dynamic/v1/portal）

/// 动态页顶上那一排头像里的一个 UP 主。
struct FollowedUp: Decodable, Identifiable, Hashable, Sendable {
    let mid: Int
    let uname: String
    let face: String
    /// 有没有未读更新。头像上的小红点就是它。
    let hasUpdate: Bool

    var id: Int { mid }
    var secureAvatarURL: URL? { URL.biliSecure(face) }

    enum CodingKeys: String, CodingKey {
        case mid, uname, face
        case hasUpdate = "has_update"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let mid = container.flexibleInt(forKey: .mid) else {
            throw DecodingError.dataCorruptedError(
                forKey: .mid,
                in: container,
                debugDescription: "关注的 UP 主必须有 mid"
            )
        }
        self.mid = mid
        uname = container.flexibleString(forKey: .uname) ?? ""
        face = container.flexibleString(forKey: .face) ?? ""
        hasUpdate = container.flexibleBool(forKey: .hasUpdate) ?? false
    }

    init(mid: Int, uname: String, face: String, hasUpdate: Bool) {
        self.mid = mid
        self.uname = uname
        self.face = face
        self.hasUpdate = hasUpdate
    }
}

struct DynamicPortalPayload: Decodable, Sendable {
    let upList: [FollowedUp]?

    enum CodingKeys: String, CodingKey {
        case upList = "up_list"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        upList = (try? container.decodeIfPresent(LenientList<FollowedUp>.self, forKey: .upList))??.elements
    }
}

// MARK: - 动态流里的一条内容

/// 关注页和 UP 主动态页共用的展示模型。
///
/// 一条动态可能是视频投稿（带 `video`）、纯文字（只有 `text`）或图文
/// （`text` + `images`），三者共用同一张卡片，缺哪块就不画哪块。
struct DynamicEntry: Identifiable, Hashable, Sendable {
    let id: String
    let authorMid: Int
    let authorName: String
    let authorFace: String
    /// 「3小时前」这类相对时间。
    let publishedText: String
    /// 正文。视频动态这里是 UP 主写的推荐语，可能为空。
    let text: String
    let images: [DynamicImage]
    let video: FollowedVideo?

    let likeCount: Int
    let commentCount: Int
    let forwardCount: Int
    /// 接口回报的点赞状态。界面上的即时状态由列表的视图模型叠加。
    let isLikedByServer: Bool

    /// 评论区定位：`oid` 是 `comment_id_str`，`type` 是动态自己的评论区类型
    /// （视频 1、图文 11、纯文字 17）。两个都拿到才有评论可看。
    let commentOid: Int
    let commentType: Int
    var publishedTimestamp: Int = 0
    var vote: DynamicVote? = nil

    var secureAvatarURL: URL? { URL.biliSecure(authorFace) }
    var hasComments: Bool { commentOid > 0 && commentType > 0 }
}

/// 图文动态里的一张图。宽高用来决定单图时的显示比例。
struct DynamicImage: Identifiable, Hashable, Sendable {
    let url: String
    let width: Int
    let height: Int

    var id: String { url }
    var secureURL: URL? { URL.biliSecure(url) }

    /// 单图动态按原图比例显示，但压在 3:4 到 16:9 之间，
    /// 免得一张长图把整屏占满。
    var displayAspectRatio: CGFloat {
        guard width > 0, height > 0 else { return 16.0 / 9.0 }
        return min(max(CGFloat(width) / CGFloat(height), 0.75), 16.0 / 9.0)
    }
}

// MARK: - 关注动态流（x/polymer/web-dynamic/v1/feed/all）

/// 一页动态。翻页靠 `offset` 游标，不是页码——服务端按它继续往下取。
///
/// 这个接口的字段类型并不稳定（`offset` 有时是字符串有时是数字，`has_more`
/// 有时是布尔有时是 0/1），而且一页里混着各种类型的动态。所以每个标量都按
/// 「两种都接」解，条目列表则逐条解、解不动就跳过：一条没见过的动态不该让
/// 整页变成「数据解析失败」。
struct DynamicFeedPage: Decodable, Sendable {
    let items: [DynamicItem]
    let offset: String
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case items, offset
        case hasMore = "has_more"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? container.decodeIfPresent(LenientList<DynamicItem>.self, forKey: .items))??.elements ?? []
        offset = container.flexibleString(forKey: .offset) ?? ""
        hasMore = container.flexibleBool(forKey: .hasMore) ?? false
    }

    /// 这一页里能展示的内容：视频投稿（含合集更新）、纯文字、图文。
    /// 转发、直播预约、番剧这些结构对不上的类型在 `asEntry` 里被挡掉。
    var entries: [DynamicEntry] {
        items.compactMap(\.asEntry)
    }
}

/// 一条动态。字段一律按可选解码：动态类型很多（图文、专栏、直播预约、转发），
/// 其中一条结构不同不该让整页解析失败。
struct DynamicItem: Decodable, Sendable {
    let idStr: String?
    /// `DYNAMIC_TYPE_AV` / `DYNAMIC_TYPE_WORD` / `DYNAMIC_TYPE_DRAW` …
    let type: String?
    let basic: Basic?
    let modules: Modules?

    /// 这个 App 会画出来的动态类型。转发、直播预约、番剧这些结构差别太大，
    /// 直接不收——列表里宁可少一条，也不要一张画不明白的卡片。
    private static let supportedTypes: Set<String> = [
        "DYNAMIC_TYPE_AV",
        "DYNAMIC_TYPE_UGC_SEASON",
        "DYNAMIC_TYPE_WORD",
        "DYNAMIC_TYPE_DRAW"
    ]

    enum CodingKeys: String, CodingKey {
        case idStr = "id_str"
        case id
        case type, basic, modules
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // id 太大时服务端只保证 id_str 是准的，两个键都试。
        idStr = container.flexibleString(forKey: .idStr) ?? container.flexibleString(forKey: .id)
        type = container.flexibleString(forKey: .type)
        basic = try? container.decodeIfPresent(Basic.self, forKey: .basic)
        modules = try? container.decodeIfPresent(Modules.self, forKey: .modules)
    }

    /// 评论区的定位信息就挂在这一层。
    struct Basic: Decodable, Sendable {
        let commentIdStr: Int?
        let commentType: Int?

        enum CodingKeys: String, CodingKey {
            case commentIdStr = "comment_id_str"
            case commentType = "comment_type"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            commentIdStr = container.flexibleInt(forKey: .commentIdStr)
            commentType = container.flexibleInt(forKey: .commentType)
        }
    }

    struct Modules: Decodable, Sendable {
        let author: Author?
        let dynamic: DynamicModule?
        let stat: StatModule?

        enum CodingKeys: String, CodingKey {
            case author = "module_author"
            case dynamic = "module_dynamic"
            case stat = "module_stat"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            author = try? container.decodeIfPresent(Author.self, forKey: .author)
            dynamic = try? container.decodeIfPresent(DynamicModule.self, forKey: .dynamic)
            stat = try? container.decodeIfPresent(StatModule.self, forKey: .stat)
        }
    }

    struct Author: Decodable, Sendable {
        let mid: Int?
        let name: String?
        let face: String?
        /// 服务端排好版的相对时间，例如「3小时前」。
        let pubTime: String?
        let pubTs: Int?

        enum CodingKeys: String, CodingKey {
            case mid, name, face
            case pubTime = "pub_time"
            case pubTs = "pub_ts"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            mid = container.flexibleInt(forKey: .mid)
            name = container.flexibleString(forKey: .name)
            face = container.flexibleString(forKey: .face)
            pubTime = container.flexibleString(forKey: .pubTime)
            pubTs = container.flexibleInt(forKey: .pubTs)
        }
    }

    /// 点赞 / 评论 / 转发三个数字，以及自己有没有点过赞。
    struct StatModule: Decodable, Sendable {
        let comment: Counter?
        let forward: Counter?
        let like: LikeCounter?

        enum CodingKeys: String, CodingKey {
            case comment, forward, like
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            comment = try? container.decodeIfPresent(Counter.self, forKey: .comment)
            forward = try? container.decodeIfPresent(Counter.self, forKey: .forward)
            like = try? container.decodeIfPresent(LikeCounter.self, forKey: .like)
        }

        struct Counter: Decodable, Sendable {
            let count: Int?

            enum CodingKeys: String, CodingKey { case count }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                count = container.flexibleInt(forKey: .count)
            }
        }

        struct LikeCounter: Decodable, Sendable {
            let count: Int?
            /// 自己有没有点过赞。
            let status: Bool?

            enum CodingKeys: String, CodingKey { case count, status }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                count = container.flexibleInt(forKey: .count)
                status = container.flexibleBool(forKey: .status)
            }
        }
    }

    struct DynamicModule: Decodable, Sendable {
        /// 正文。图文和纯文字动态的文字在这里。
        let desc: Description?
        let major: Major?
        let additional: Additional?

        struct Additional: Decodable, Sendable {
            let vote: DynamicVote?
        }

        enum CodingKeys: String, CodingKey {
            case desc, major, additional
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            desc = try? container.decodeIfPresent(Description.self, forKey: .desc)
            major = try? container.decodeIfPresent(Major.self, forKey: .major)
            additional = try? container.decodeIfPresent(Additional.self, forKey: .additional)
        }

        struct Description: Decodable, Sendable {
            let text: String?

            enum CodingKeys: String, CodingKey { case text }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                text = container.flexibleString(forKey: .text)
            }
        }
    }

    /// 动态的主体。请求里带了 `features=itemOpusStyle`，所以图文既可能落在
    /// 老的 `draw` 上，也可能落在新的 `opus` 上，两种都解。
    struct Major: Decodable, Sendable {
        let archive: Archive?
        let draw: Draw?
        let opus: Opus?

        enum CodingKeys: String, CodingKey {
            case archive, draw, opus
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            archive = try? container.decodeIfPresent(Archive.self, forKey: .archive)
            draw = try? container.decodeIfPresent(Draw.self, forKey: .draw)
            opus = try? container.decodeIfPresent(Opus.self, forKey: .opus)
        }

        struct Draw: Decodable, Sendable {
            let items: [Picture]?

            enum CodingKeys: String, CodingKey { case items }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                items = (try? container.decodeIfPresent(LenientList<Picture>.self, forKey: .items))??.elements
            }
        }

        struct Opus: Decodable, Sendable {
            let title: String?
            let summary: DynamicModule.Description?
            let pics: [Picture]?

            enum CodingKeys: String, CodingKey { case title, summary, pics }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                title = container.flexibleString(forKey: .title)
                summary = try? container.decodeIfPresent(DynamicModule.Description.self, forKey: .summary)
                pics = (try? container.decodeIfPresent(LenientList<Picture>.self, forKey: .pics))??.elements
            }
        }

        /// 一张图。老结构的键是 `src`，新结构（opus）是 `url`，两个都认。
        struct Picture: Decodable, Sendable {
            let src: String?
            let width: Int?
            let height: Int?

            enum CodingKeys: String, CodingKey {
                case src, url, width, height
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                src = container.flexibleString(forKey: .src) ?? container.flexibleString(forKey: .url)
                width = container.flexibleInt(forKey: .width)
                height = container.flexibleInt(forKey: .height)
            }

            var asImage: DynamicImage? {
                guard let src, !src.isEmpty else { return nil }
                return DynamicImage(url: src, width: width ?? 0, height: height ?? 0)
            }
        }
    }

    /// 动态里的视频稿件。注意 `aid` 在这个接口里是字符串，
    /// 而站内其它接口给的是数字，所以两种都接。
    struct Archive: Decodable, Sendable {
        let aid: Int?
        let bvid: String?
        let title: String?
        let cover: String?
        let durationText: String?
        let stat: Stat?

        enum CodingKeys: String, CodingKey {
            case aid, bvid, title, cover, stat
            case durationText = "duration_text"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            aid = container.flexibleInt(forKey: .aid)
            bvid = container.flexibleString(forKey: .bvid)
            title = container.flexibleString(forKey: .title)
            cover = container.flexibleString(forKey: .cover)
            durationText = container.flexibleString(forKey: .durationText)
            stat = try? container.decodeIfPresent(Stat.self, forKey: .stat)
        }

        /// 播放量和弹幕数在动态接口里通常已经是「1.2万」这样的成品文字，
        /// 个别稿件回的是裸数字，所以这里也按「两种都接」处理。
        struct Stat: Decodable, Sendable {
            let play: String?
            let danmaku: String?

            enum CodingKeys: String, CodingKey {
                case play, danmaku
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                play = container.flexibleString(forKey: .play)
                danmaku = container.flexibleString(forKey: .danmaku)
            }
        }
    }

    /// 视频动态里的那张视频卡片。不是视频动态就没有。
    var asFollowedVideo: FollowedVideo? {
        guard let archive = modules?.dynamic?.major?.archive,
              let bvid = archive.bvid, !bvid.isEmpty
        else { return nil }
        let author = modules?.author
        return FollowedVideo(
            id: idStr ?? bvid,
            bvid: bvid,
            aid: archive.aid ?? 0,
            title: archive.title ?? "",
            cover: archive.cover ?? "",
            durationText: archive.durationText ?? "",
            playText: archive.stat?.play ?? "",
            authorMid: author?.mid ?? 0,
            authorName: author?.name ?? "",
            authorFace: author?.face ?? "",
            publishedText: author?.pubTime ?? ""
        )
    }

    /// 收敛成列表要画的那个模型。类型不在白名单里，或者三块内容
    /// （视频 / 文字 / 图片）一块都没有，就当这条动态不存在。
    var asEntry: DynamicEntry? {
        let video = asFollowedVideo
        let kind = type ?? (video != nil ? "DYNAMIC_TYPE_AV" : "")
        guard Self.supportedTypes.contains(kind) else { return nil }

        let dynamic = modules?.dynamic
        let opus = dynamic?.major?.opus
        let body = dynamic?.desc?.text ?? opus?.summary?.text ?? ""
        let text = [opus?.title, body]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        let pictures = opus?.pics ?? dynamic?.major?.draw?.items ?? []
        let images = pictures.compactMap(\.asImage)

        guard video != nil || !text.isEmpty || !images.isEmpty || dynamic?.additional?.vote != nil else { return nil }
        guard let id = idStr ?? video?.bvid else { return nil }

        let author = modules?.author
        let stat = modules?.stat
        return DynamicEntry(
            id: id,
            authorMid: author?.mid ?? 0,
            authorName: author?.name ?? "",
            authorFace: author?.face ?? "",
            publishedText: author?.pubTime ?? "",
            text: text,
            images: images,
            video: video,
            likeCount: stat?.like?.count ?? 0,
            commentCount: stat?.comment?.count ?? 0,
            forwardCount: stat?.forward?.count ?? 0,
            isLikedByServer: stat?.like?.status ?? false,
            commentOid: basic?.commentIdStr ?? 0,
            commentType: basic?.commentType ?? 0,
            publishedTimestamp: author?.pubTs ?? 0,
            vote: dynamic?.additional?.vote
        )
    }
}

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
struct SpaceVideo: Decodable, Identifiable, Hashable, Sendable {
    let aid: Int
    let bvid: String
    let title: String
    let pic: String
    let length: String
    let play: Int
    let author: String
    let mid: Int
    let created: Int

    var id: String { bvid }

    enum CodingKeys: String, CodingKey {
        case aid, bvid, title, pic, length, play, author, mid, created
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
            publishedText: created > 0 ? created.biliRelativeTimeText : ""
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

// MARK: - 解码小工具

/// 逐条解码的数组：解不出来的那一条直接跳过，其余照常返回。
///
/// 动态流一页里混着投稿、合集、直播预约、番剧等好几种结构，用普通的
/// `[T]` 解码时，只要有一条对不上，整页就会失败——用户看到的是一片
/// 「数据解析失败」。列表类接口一律走这个类型。
struct LenientList<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var collected: [Element] = []
        while !container.isAtEnd {
            let indexBefore = container.currentIndex
            if let element = try? container.decode(Element.self) {
                collected.append(element)
            } else {
                // 解不出来的那一条也必须消费掉，否则游标停在原地。
                _ = try? container.decode(IgnoredValue.self)
            }
            // 兜底：万一两次解码都没能推进游标，立刻停手，绝不在这里空转。
            if container.currentIndex == indexBefore { break }
        }
        elements = collected
    }
}

/// 只为了把一条解不动的数据「读掉」而存在，本身不保留任何内容。
private struct IgnoredValue: Decodable {
    init(from decoder: Decoder) throws {}
}

extension KeyedDecodingContainer {
    /// B 站有些字段同一个含义在不同接口、不同稿件上一会儿是数字、一会儿是
    /// 字符串（动态流的 `aid`、隐藏播放量时的 `--`），两种都试一遍。
    func flexibleInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let text = try? decodeIfPresent(String.self, forKey: key) { return Int(text) }
        return nil
    }

    /// 同上，反过来：本该是文字的字段偶尔会回一个数字（动态 id、播放量）。
    func flexibleString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return String(value) }
        return nil
    }

    /// 开关字段有时是 true/false，有时是 1/0，也见过 "true"。
    func flexibleBool(forKey key: Key) -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        if let text = try? decodeIfPresent(String.self, forKey: key) {
            return text == "true" || text == "1"
        }
        return nil
    }
}
