import Foundation

/// 评论接口 `x/v2/reply` 的返回。
///
/// 接口里单条评论有三十多个字段，这里只解码界面真正用到的那几个：
/// 全量建模的话，B 站任何一次字段调整都会让整页评论解析失败。
struct CommentPage: Decodable, Sendable {
    let page: CommentPageInfo
    let replies: [Comment]?
}

struct CommentPageInfo: Decodable, Sendable {
    /// 当前页码。
    let num: Int
    /// 每页条数。
    let size: Int
    /// 一级评论的总条数，底部标签栏上显示的就是它。
    let count: Int
}

/// 展开某条评论下全部回复时的返回。
struct CommentReplyPage: Decodable, Sendable {
    let page: CommentPageInfo
    let replies: [Comment]?
}

struct CommentMember: Decodable, Hashable, Sendable {
    let uname: String
    let avatar: String

    var secureAvatarURL: URL? { URL.biliSecure(avatar) }
}

struct CommentContent: Decodable, Hashable, Sendable {
    let message: String
    /// 正文里出现过的表情。键就是正文里那段字面量，例如 `[doge]`。
    /// 只有用到表情的评论才有这个字段。
    let emote: [String: CommentEmote]?
    /// 图文评论的配图。宽松解码：这个字段的形态并不稳定，
    /// 解不动的时候当作没有配图，不能连累整页评论。
    let pictures: [CommentPicture]

    enum CodingKeys: String, CodingKey {
        case message, emote, pictures
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decode(String.self, forKey: .message)
        emote = try? container.decodeIfPresent([String: CommentEmote].self, forKey: .emote)
        pictures = (try? container.decodeIfPresent(LenientList<CommentPicture>.self, forKey: .pictures))??.elements ?? []
    }
}

/// 评论里的一张配图。
struct CommentPicture: Decodable, Hashable, Sendable, Identifiable {
    let imgSrc: String
    let imgWidth: Int?
    let imgHeight: Int?

    enum CodingKeys: String, CodingKey {
        case imgSrc = "img_src"
        case imgWidth = "img_width"
        case imgHeight = "img_height"
    }

    var id: String { imgSrc }
    var secureURL: URL? { URL.biliSecure(imgSrc) }

    /// 单图按原图比例显示，压在 3:4 到 16:9 之间，和动态里的单图一个规矩。
    var displayAspectRatio: CGFloat {
        guard let imgWidth, let imgHeight, imgWidth > 0, imgHeight > 0 else { return 4.0 / 3.0 }
        return min(max(CGFloat(imgWidth) / CGFloat(imgHeight), 0.75), 16.0 / 9.0)
    }
}

/// 评论里的一个表情。
///
/// 正文本身仍然是纯文本（`[doge]`），要显示成图得靠这张表里的 `url` 去换。
/// 没有这张表时就按原样显示那段方括号文字，和网页端未登录时的表现一致。
struct CommentEmote: Decodable, Hashable, Sendable {
    let url: String
    let meta: Meta?

    struct Meta: Decodable, Hashable, Sendable {
        /// 1 是跟文字同高的行内小表情，2 是单独占一行的大表情。
        let size: Int?
    }

    var secureURL: URL? { URL.biliSecure(url) }

    /// 大表情画得比正文高一截，和官方一致。
    var heightMultiplier: CGFloat { (meta?.size ?? 1) >= 2 ? 2.4 : 1.3 }
}

struct Comment: Decodable, Identifiable, Hashable, Sendable {
    let rpid: Int
    /// 秒级时间戳。
    let ctime: Int
    let like: Int
    /// 这条评论下面一共有多少条回复。
    let rcount: Int
    let member: CommentMember
    let content: CommentContent
    /// 当前账号有没有给这条评论点过赞：1 是点过。未登录时接口返回 0。
    let action: Int?
    /// 接口自带的楼中楼预览，最多 3 条。这部分是跟着一级评论一起返回的，
    /// 显示它们不需要任何额外请求。
    let replies: [Comment]?

    var id: Int { rpid }

    var message: String { content.message }

    /// 正文里用到的表情表。没有表情的评论是空字典。
    var emotes: [String: CommentEmote] { content.emote ?? [:] }

    /// 图文评论的配图。没有配图时是空数组。
    var pictures: [CommentPicture] { content.pictures }

    /// 接口回报的点赞状态。界面上的即时状态由 `CommentsViewModel` 叠加，
    /// 因为点完之后不会为了一个按钮把整页评论重新拉一遍。
    var isLikedByServer: Bool { action == 1 }

    /// 把时间戳变成“3天前”这类相对说法；超过一年就直接显示日期。
    var relativeTime: String {
        let minute: TimeInterval = 60
        let hour: TimeInterval = 60 * 60
        let day: TimeInterval = 24 * hour
        let elapsed = Date().timeIntervalSince1970 - TimeInterval(ctime)

        if elapsed < minute { return "刚刚" }
        if elapsed < hour { return "\(Int(elapsed / minute))分钟前" }
        if elapsed < day { return "\(Int(elapsed / hour))小时前" }
        if elapsed < day * 30 { return "\(Int(elapsed / day))天前" }
        if elapsed < day * 365 { return "\(Int(elapsed / day / 30))个月前" }
        return Date(timeIntervalSince1970: TimeInterval(ctime))
            .formatted(.dateTime.year().month().day())
    }
}
