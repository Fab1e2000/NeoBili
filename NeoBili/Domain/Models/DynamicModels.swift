import Foundation

// MARK: - 动态流里的一条内容

/// 关注页和 UP 主动态页共用的展示模型。
///
/// 一条动态可能是视频投稿（带 `video`）、纯文字（只有 `text`）或图文
/// （`text` + `images`），三者共用同一张卡片，缺哪块就不画哪块。
public struct DynamicEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public let authorMid: Int
    public let authorName: String
    public let authorFace: String
    /// 「3小时前」这类相对时间。
    public let publishedText: String
    /// 正文。视频动态这里是 UP 主写的推荐语，可能为空。
    public let text: String
    /// 正文里用到的表情表，键是正文里那段方括号字面量。没有表情时是空字典。
    public var emotes: [String: CommentEmote] = [:]
    public let images: [DynamicImage]
    public let video: FollowedVideo?

    public let likeCount: Int
    public let commentCount: Int
    public let forwardCount: Int
    /// 接口回报的点赞状态。界面上的即时状态由列表的视图模型叠加。
    public let isLikedByServer: Bool

    /// 评论区定位：`oid` 是 `comment_id_str`，`type` 是动态自己的评论区类型
    /// （视频 1、图文 11、纯文字 17）。两个都拿到才有评论可看。
    public let commentOid: Int
    public let commentType: Int
    public var publishedTimestamp: Int = 0
    public var vote: DynamicVote? = nil

    public var secureAvatarURL: URL? { URL.biliSecure(authorFace) }
    public var hasComments: Bool { commentOid > 0 && commentType > 0 }
}

/// 图文动态里的一张图。宽高用来决定单图时的显示比例。
public struct DynamicImage: Identifiable, Hashable, Sendable {
    public let url: String
    public let width: Int
    public let height: Int

    public var id: String { url }
    public var secureURL: URL? { URL.biliSecure(url) }

    /// 单图动态按原图比例显示，但压在 3:4 到 16:9 之间，
    /// 免得一张长图把整屏占满。
    public var displayAspectRatio: CGFloat {
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
public struct DynamicFeedPage: Decodable, Sendable {
    public let items: [DynamicItem]
    public let offset: String
    public let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case items, offset
        case hasMore = "has_more"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? container.decodeIfPresent(LenientList<DynamicItem>.self, forKey: .items))??.elements ?? []
        offset = container.flexibleString(forKey: .offset) ?? ""
        hasMore = container.flexibleBool(forKey: .hasMore) ?? false
    }

    /// 这一页里能展示的内容：视频投稿（含合集更新）、纯文字、图文。
    /// 转发、直播预约、番剧这些结构对不上的类型在 `asEntry` 里被挡掉。
    public var entries: [DynamicEntry] {
        items.compactMap(\.asEntry)
    }
}

/// 一条动态。字段一律按可选解码：动态类型很多（图文、专栏、直播预约、转发），
/// 其中一条结构不同不该让整页解析失败。
public struct DynamicItem: Decodable, Sendable {
    public let idStr: String?
    /// `DYNAMIC_TYPE_AV` / `DYNAMIC_TYPE_WORD` / `DYNAMIC_TYPE_DRAW` …
    public let type: String?
    public let basic: Basic?
    public let modules: Modules?

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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // id 太大时服务端只保证 id_str 是准的，两个键都试。
        idStr = container.flexibleString(forKey: .idStr) ?? container.flexibleString(forKey: .id)
        type = container.flexibleString(forKey: .type)
        basic = try? container.decodeIfPresent(Basic.self, forKey: .basic)
        modules = try? container.decodeIfPresent(Modules.self, forKey: .modules)
    }

    /// 评论区的定位信息就挂在这一层。
    public struct Basic: Decodable, Sendable {
        public let commentIdStr: Int?
        public let commentType: Int?

        enum CodingKeys: String, CodingKey {
            case commentIdStr = "comment_id_str"
            case commentType = "comment_type"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            commentIdStr = container.flexibleInt(forKey: .commentIdStr)
            commentType = container.flexibleInt(forKey: .commentType)
        }
    }

    public struct Modules: Decodable, Sendable {
        public let author: Author?
        public let dynamic: DynamicModule?
        public let stat: StatModule?

        enum CodingKeys: String, CodingKey {
            case author = "module_author"
            case dynamic = "module_dynamic"
            case stat = "module_stat"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            author = try? container.decodeIfPresent(Author.self, forKey: .author)
            dynamic = try? container.decodeIfPresent(DynamicModule.self, forKey: .dynamic)
            stat = try? container.decodeIfPresent(StatModule.self, forKey: .stat)
        }
    }

    public struct Author: Decodable, Sendable {
        public let mid: Int?
        public let name: String?
        public let face: String?
        /// 服务端排好版的相对时间，例如「3小时前」。
        public let pubTime: String?
        public let pubTs: Int?

        enum CodingKeys: String, CodingKey {
            case mid, name, face
            case pubTime = "pub_time"
            case pubTs = "pub_ts"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            mid = container.flexibleInt(forKey: .mid)
            name = container.flexibleString(forKey: .name)
            face = container.flexibleString(forKey: .face)
            pubTime = container.flexibleString(forKey: .pubTime)
            pubTs = container.flexibleInt(forKey: .pubTs)
        }
    }

    /// 点赞 / 评论 / 转发三个数字，以及自己有没有点过赞。
    public struct StatModule: Decodable, Sendable {
        public let comment: Counter?
        public let forward: Counter?
        public let like: LikeCounter?

        enum CodingKeys: String, CodingKey {
            case comment, forward, like
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            comment = try? container.decodeIfPresent(Counter.self, forKey: .comment)
            forward = try? container.decodeIfPresent(Counter.self, forKey: .forward)
            like = try? container.decodeIfPresent(LikeCounter.self, forKey: .like)
        }

        public struct Counter: Decodable, Sendable {
            public let count: Int?

            enum CodingKeys: String, CodingKey { case count }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                count = container.flexibleInt(forKey: .count)
            }
        }

        public struct LikeCounter: Decodable, Sendable {
            public let count: Int?
            /// 自己有没有点过赞。
            public let status: Bool?

            enum CodingKeys: String, CodingKey { case count, status }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                count = container.flexibleInt(forKey: .count)
                status = container.flexibleBool(forKey: .status)
            }
        }
    }

    public struct DynamicModule: Decodable, Sendable {
        /// 正文。图文和纯文字动态的文字在这里。
        public let desc: Description?
        public let major: Major?
        public let additional: Additional?

        public struct Additional: Decodable, Sendable {
            public let vote: DynamicVote?
        }

        enum CodingKeys: String, CodingKey {
            case desc, major, additional
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            desc = try? container.decodeIfPresent(Description.self, forKey: .desc)
            major = try? container.decodeIfPresent(Major.self, forKey: .major)
            additional = try? container.decodeIfPresent(Additional.self, forKey: .additional)
        }

        public struct Description: Decodable, Sendable {
            public let text: String?
            /// 正文里用到的表情，键就是正文里那段字面量（例如
            /// `[UPOWER_1150976664_戳手手]`）。和评论共用 `CommentEmote`，
            /// 这样两边可以用同一个 `CommentEmoteText` 去画。
            public let emotes: [String: CommentEmote]

            enum CodingKeys: String, CodingKey {
                case text
                case richTextNodes = "rich_text_nodes"
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                text = container.flexibleString(forKey: .text)
                // 正文本身仍然是纯文本，表情要靠这张富文本节点表去换图。
                // 这张表解不动时按原样显示方括号文字，和网页端未登录时一致。
                let nodes = (try? container.decodeIfPresent(
                    LenientList<RichTextNode>.self, forKey: .richTextNodes
                ))??.elements ?? []
                emotes = Dictionary(nodes.compactMap(\.asEmote)) { first, _ in first }
            }
        }

        /// 富文本节点。这里只关心表情那一种，其余（@某人、话题、链接）
        /// 的文字已经在 `text` 里了，不必重复处理。
        public struct RichTextNode: Decodable, Sendable {
            public let text: String?
            public let emoji: Emoji?

            public struct Emoji: Decodable, Sendable {
                public let iconURL: String?
                /// 1 是跟文字同高的小表情，2 是大表情，和评论里的含义一致。
                public let size: Int?

                enum CodingKeys: String, CodingKey {
                    case iconURL = "icon_url"
                    case size
                }
            }

            public var asEmote: (String, CommentEmote)? {
                guard let text, !text.isEmpty,
                      let icon = emoji?.iconURL, !icon.isEmpty
                else { return nil }
                return (text, CommentEmote(url: icon, meta: .init(size: emoji?.size)))
            }
        }
    }

    /// 动态的主体。请求里带了 `features=itemOpusStyle`，所以图文既可能落在
    /// 老的 `draw` 上，也可能落在新的 `opus` 上，两种都解。
    public struct Major: Decodable, Sendable {
        public let archive: Archive?
        public let draw: Draw?
        public let opus: Opus?

        enum CodingKeys: String, CodingKey {
            case archive, draw, opus
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            archive = try? container.decodeIfPresent(Archive.self, forKey: .archive)
            draw = try? container.decodeIfPresent(Draw.self, forKey: .draw)
            opus = try? container.decodeIfPresent(Opus.self, forKey: .opus)
        }

        public struct Draw: Decodable, Sendable {
            public let items: [Picture]?

            enum CodingKeys: String, CodingKey { case items }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                items = (try? container.decodeIfPresent(LenientList<Picture>.self, forKey: .items))??.elements
            }
        }

        public struct Opus: Decodable, Sendable {
            public let title: String?
            public let summary: DynamicModule.Description?
            public let pics: [Picture]?

            enum CodingKeys: String, CodingKey { case title, summary, pics }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                title = container.flexibleString(forKey: .title)
                summary = try? container.decodeIfPresent(DynamicModule.Description.self, forKey: .summary)
                pics = (try? container.decodeIfPresent(LenientList<Picture>.self, forKey: .pics))??.elements
            }
        }

        /// 一张图。老结构的键是 `src`，新结构（opus）是 `url`，两个都认。
        public struct Picture: Decodable, Sendable {
            public let src: String?
            public let width: Int?
            public let height: Int?

            enum CodingKeys: String, CodingKey {
                case src, url, width, height
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                src = container.flexibleString(forKey: .src) ?? container.flexibleString(forKey: .url)
                width = container.flexibleInt(forKey: .width)
                height = container.flexibleInt(forKey: .height)
            }

            public var asImage: DynamicImage? {
                guard let src, !src.isEmpty else { return nil }
                return DynamicImage(url: src, width: width ?? 0, height: height ?? 0)
            }
        }
    }

    /// 动态里的视频稿件。注意 `aid` 在这个接口里是字符串，
    /// 而站内其它接口给的是数字，所以两种都接。
    public struct Archive: Decodable, Sendable {
        public let aid: Int?
        public let bvid: String?
        public let title: String?
        public let cover: String?
        public let durationText: String?
        public let stat: Stat?
        public let dimension: VideoDimension?

        enum CodingKeys: String, CodingKey {
            case aid, bvid, title, cover, stat, dimension
            case durationText = "duration_text"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            aid = container.flexibleInt(forKey: .aid)
            bvid = container.flexibleString(forKey: .bvid)
            title = container.flexibleString(forKey: .title)
            cover = container.flexibleString(forKey: .cover)
            durationText = container.flexibleString(forKey: .durationText)
            stat = try? container.decodeIfPresent(Stat.self, forKey: .stat)
            dimension = try? container.decodeIfPresent(VideoDimension.self, forKey: .dimension)
        }

        /// 播放量和弹幕数在动态接口里通常已经是「1.2万」这样的成品文字，
        /// 个别稿件回的是裸数字，所以这里也按「两种都接」处理。
        public struct Stat: Decodable, Sendable {
            public let play: String?
            public let danmaku: String?

            enum CodingKeys: String, CodingKey {
                case play, danmaku
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                play = container.flexibleString(forKey: .play)
                danmaku = container.flexibleString(forKey: .danmaku)
            }
        }
    }

    /// 视频动态里的那张视频卡片。不是视频动态就没有。
    public var asFollowedVideo: FollowedVideo? {
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
            publishedText: author?.pubTime ?? "",
            dimension: archive.dimension
        )
    }

    /// 收敛成列表要画的那个模型。类型不在白名单里，或者三块内容
    /// （视频 / 文字 / 图片）一块都没有，就当这条动态不存在。
    public var asEntry: DynamicEntry? {
        let video = asFollowedVideo
        let kind = type ?? (video != nil ? "DYNAMIC_TYPE_AV" : "")
        guard Self.supportedTypes.contains(kind) else { return nil }

        let dynamic = modules?.dynamic
        let opus = dynamic?.major?.opus
        let body = dynamic?.desc?.text ?? opus?.summary?.text ?? ""
        // 标题和正文各自带一份表情表，合起来给整条动态用。
        let emotes = (dynamic?.desc?.emotes ?? [:])
            .merging(opus?.summary?.emotes ?? [:]) { existing, _ in existing }
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
            emotes: emotes,
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
