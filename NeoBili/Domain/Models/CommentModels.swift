import Foundation

/// 评论接口 `x/v2/reply` 的返回。
///
/// 接口里单条评论有三十多个字段，这里只解码界面真正用到的那几个：
/// 全量建模的话，B 站任何一次字段调整都会让整页评论解析失败。
public struct CommentPage: Decodable, Sendable {
    public let page: CommentPageInfo
    public let replies: [Comment]?
    public let uploaderID: Int?
    public let pinnedReplies: [Comment]

    public init(page: CommentPageInfo, replies: [Comment]?, uploaderID: Int? = nil, pinnedReplies: [Comment] = []) {
        self.page = page
        self.replies = replies
        self.uploaderID = uploaderID
        self.pinnedReplies = pinnedReplies
    }

    private enum CodingKeys: String, CodingKey { case page, replies, upper, top, topReplies = "top_replies" }
    private enum UpperKeys: String, CodingKey { case mid, top }
    private enum TopKeys: String, CodingKey { case upper, admin }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        page = try c.decode(CommentPageInfo.self, forKey: .page)
        replies = try c.decodeIfPresent([Comment].self, forKey: .replies)
        let upper = try? c.nestedContainer(keyedBy: UpperKeys.self, forKey: .upper)
        uploaderID = upper?.commentID(forKey: .mid)
        let top = try? c.nestedContainer(keyedBy: TopKeys.self, forKey: .top)
        let listed = (try? c.decode(LenientList<Comment>.self, forKey: .topReplies).elements) ?? []
        let individual = [try? upper?.decode(Comment.self, forKey: .top),
                          try? top?.decode(Comment.self, forKey: .upper),
                          try? top?.decode(Comment.self, forKey: .admin)].compactMap { $0 }
        var seen: Set<Int> = []
        pinnedReplies = (listed + individual).filter { seen.insert($0.id).inserted }
    }
}

public enum CommentSort: Int, CaseIterable, Sendable {
    case hot = 1
    case latest = 0
}

public struct CommentPageInfo: Decodable, Sendable {
    /// 当前页码。
    public let num: Int
    /// 每页条数。
    public let size: Int
    /// 一级评论的总条数；分页只使用这个数。
    public let count: Int
    /// 全部评论及回复数。旧响应可能不提供。
    public let allCount: Int?

    public init(num: Int, size: Int, count: Int, allCount: Int? = nil) {
        self.num = num; self.size = size; self.count = count; self.allCount = allCount
    }
    private enum CodingKeys: String, CodingKey { case num, size, count, allCount = "acount" }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        num = try c.decode(Int.self, forKey: .num)
        size = try c.decode(Int.self, forKey: .size)
        count = try c.decode(Int.self, forKey: .count)
        allCount = (try? c.decode(Int.self, forKey: .allCount)).flatMap { $0 >= 0 ? $0 : nil }
    }
}

/// 展开某条评论下全部回复时的返回。
public struct CommentReplyPage: Decodable, Sendable {
    public let page: CommentPageInfo
    public let replies: [Comment]?
}

public struct CommentMember: Decodable, Hashable, Sendable {
    public let mid: Int?
    public let uname: String
    public let avatar: String

    public var secureAvatarURL: URL? { URL.biliSecure(avatar) }

    private enum CodingKeys: String, CodingKey { case mid, uname, avatar }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mid = c.commentID(forKey: .mid)
        uname = try c.decode(String.self, forKey: .uname)
        avatar = try c.decode(String.self, forKey: .avatar)
    }
}

private extension KeyedDecodingContainer {
    /// IDs are integers, never truncated floating-point values or display names.
    func commentID(forKey key: Key) -> Int? {
        let value = (try? decode(Int.self, forKey: key)) ?? (try? decode(String.self, forKey: key)).flatMap(Int.init)
        return value.flatMap { $0 > 0 ? $0 : nil }
    }
}

public struct CommentUPAction: Decodable, Hashable, Sendable {
    public let like: Bool
    public let reply: Bool
    private enum CodingKeys: String, CodingKey { case like, reply }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        like = (try? c.decode(Bool.self, forKey: .like)) == true
        reply = (try? c.decode(Bool.self, forKey: .reply)) == true
    }
}

public struct CommentContent: Decodable, Hashable, Sendable {
    public let message: String
    /// 正文里出现过的表情。键就是正文里那段字面量，例如 `[doge]`。
    /// 只有用到表情的评论才有这个字段。
    public let emote: [String: CommentEmote]?
    /// 图文评论的配图。宽松解码：这个字段的形态并不稳定，
    /// 解不动的时候当作没有配图，不能连累整页评论。
    public let pictures: [CommentPicture]
    public let jumpURLs: [String: CommentJumpLink]

    enum CodingKeys: String, CodingKey {
        case message, emote, pictures
        case jumpURLs = "jump_url"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = CommentTextEntities.decode(try container.decode(String.self, forKey: .message))
        let rawEmotes = try? container.decodeIfPresent([String: CommentEmote].self, forKey: .emote)
        emote = rawEmotes.map { values in
            Dictionary(values.sorted { $0.key < $1.key }.map { (CommentTextEntities.decode($0.key), $0.value) },
                       uniquingKeysWith: { first, _ in first })
        }
        let links = (try? container.decode([String: LenientCommentJumpLink].self, forKey: .jumpURLs)) ?? [:]
        jumpURLs = Dictionary(links.sorted { $0.key < $1.key }.compactMap { key, value in
            value.link.map { (CommentTextEntities.decode(key), $0) }
        }, uniquingKeysWith: { first, _ in first })
        pictures = (try? container.decodeIfPresent(LenientList<CommentPicture>.self, forKey: .pictures))??.elements ?? []
    }
}

/// 服务端提供的正文链接显示标题与 App 路由。未知字段不影响正文。
public struct CommentJumpLink: Decodable, Hashable, Sendable {
    public let title: String?
    public let appURLSchema: String?

    enum CodingKeys: String, CodingKey {
        case title
        case appURLSchema = "appUrlSchema"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decode(String.self, forKey: .title)).map(CommentTextEntities.decode)
        appURLSchema = try? c.decode(String.self, forKey: .appURLSchema)
    }
}

private struct LenientCommentJumpLink: Decodable {
    let link: CommentJumpLink?
    init(from decoder: Decoder) throws { link = try? CommentJumpLink(from: decoder) }
}

public struct CommentReplyControl: Decodable, Hashable, Sendable {
    public let location: String?
    public init(from decoder: Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        location = try? container?.decode(String.self, forKey: .location)
    }
    private enum CodingKeys: String, CodingKey { case location }
}

/// 评论里的一张配图。
public struct CommentPicture: Decodable, Hashable, Sendable, Identifiable {
    public let imgSrc: String
    public let imgWidth: Int?
    public let imgHeight: Int?

    enum CodingKeys: String, CodingKey {
        case imgSrc = "img_src"
        case imgWidth = "img_width"
        case imgHeight = "img_height"
    }

    public var id: String { imgSrc }
    public var secureURL: URL? { URL.biliSecure(imgSrc) }

    /// 单图按原图比例显示，压在 3:4 到 16:9 之间，和动态里的单图一个规矩。
    public var displayAspectRatio: CGFloat {
        guard let imgWidth, let imgHeight, imgWidth > 0, imgHeight > 0 else { return 4.0 / 3.0 }
        return min(max(CGFloat(imgWidth) / CGFloat(imgHeight), 0.75), 16.0 / 9.0)
    }
}

/// 评论里的一个表情。
///
/// 正文本身仍然是纯文本（`[doge]`），要显示成图得靠这张表里的 `url` 去换。
/// 没有这张表时就按原样显示那段方括号文字，和网页端未登录时的表现一致。
public struct CommentEmote: Decodable, Hashable, Sendable {
    public let url: String
    public let meta: Meta?

    public struct Meta: Decodable, Hashable, Sendable {
        /// 1 是跟文字同高的行内小表情，2 是单独占一行的大表情。
        public let size: Int?
    }

    public var secureURL: URL? { URL.biliSecure(url) }

    /// 大表情画得比正文高一截，和官方一致。
    public var heightMultiplier: CGFloat { (meta?.size ?? 1) >= 2 ? 2.4 : 1.3 }
}

public struct Comment: Decodable, Identifiable, Hashable, Sendable {
    public let rpid: Int
    /// 秒级时间戳。
    public let ctime: Int
    public let like: Int
    /// 这条评论下面一共有多少条回复。
    public let rcount: Int
    public let member: CommentMember
    public let content: CommentContent
    /// 当前账号有没有给这条评论点过赞：1 是点过。未登录时接口返回 0。
    public let action: Int?
    /// 接口自带的楼中楼预览，最多 3 条。这部分是跟着一级评论一起返回的，
    /// 显示它们不需要任何额外请求。
    public let replies: [Comment]?

    public let replyControl: CommentReplyControl?
    public let upAction: CommentUPAction?
    /// Root ID is absent for a root comment and can be supplied by its preview container.
    public let rootID: Int?

    enum CodingKeys: String, CodingKey {
        case rpid, ctime, like, rcount, member, content, action, replies
        case replyControl = "reply_control"
        case upAction = "up_action", rootID = "root"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rpid = try c.decode(Int.self, forKey: .rpid)
        ctime = try c.decode(Int.self, forKey: .ctime)
        like = try c.decode(Int.self, forKey: .like)
        rcount = try c.decode(Int.self, forKey: .rcount)
        member = try c.decode(CommentMember.self, forKey: .member)
        content = try c.decode(CommentContent.self, forKey: .content)
        action = try c.decodeIfPresent(Int.self, forKey: .action)
        replies = try c.decodeIfPresent([Comment].self, forKey: .replies)
        replyControl = try? c.decode(CommentReplyControl.self, forKey: .replyControl)
        upAction = try? c.decode(CommentUPAction.self, forKey: .upAction)
        rootID = c.commentID(forKey: .rootID)
    }

    public var authorID: Int? { member.mid }

    public func isAuthored(by uid: Int?) -> Bool {
        guard let uid, uid > 0, let authorID else { return false }
        return authorID == uid
    }

    /// 仅展示服务端提供的属地；不推测精确 IP 或当前位置。
    /// 服务端写作「IP属地：上海」，界面只需要地名，去掉固定前缀后返回「上海」。
    public var location: String? {
        guard var value = replyControl?.location?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        if let prefix = value.range(of: #"^IP\s*属地\s*[：:]\s*"#, options: .regularExpression) {
            value.removeSubrange(prefix)
        }
        return value.isEmpty ? nil : value
    }

    public var id: Int { rpid }

    public var message: String { content.message }

    /// 正文里用到的表情表。没有表情的评论是空字典。
    public var emotes: [String: CommentEmote] { content.emote ?? [:] }

    /// 图文评论的配图。没有配图时是空数组。
    public var pictures: [CommentPicture] { content.pictures }

    /// 接口回报的点赞状态。界面上的即时状态由 `CommentsViewModel` 叠加，
    /// 因为点完之后不会为了一个按钮把整页评论重新拉一遍。
    public var isLikedByServer: Bool { action == 1 }

    /// 把时间戳变成“3天前”这类相对说法；超过一年就直接显示「2025.04.26」这样的短日期，
    /// 和属地并排时也能留在一行里。
    public var relativeTime: String {
        let minute: TimeInterval = 60
        let hour: TimeInterval = 60 * 60
        let day: TimeInterval = 24 * hour
        let elapsed = Date().timeIntervalSince1970 - TimeInterval(ctime)

        if elapsed < minute { return String(localized: "刚刚") }
        if elapsed < hour { return String(localized: "\(Int(elapsed / minute))分钟前") }
        if elapsed < day { return String(localized: "\(Int(elapsed / hour))小时前") }
        if elapsed < day * 30 { return String(localized: "\(Int(elapsed / day))天前") }
        if elapsed < day * 365 { return String(localized: "\(Int(elapsed / day / 30))个月前") }
        return Date(timeIntervalSince1970: TimeInterval(ctime))
            .formatted(.verbatim("\(year: .defaultDigits).\(month: .twoDigits).\(day: .twoDigits)",
                                 timeZone: .current, calendar: .current))
    }
}

/// Decode escaped characters as plain text, never HTML markup or URL escapes.
/// One pass preserves intentionally escaped examples such as &amp;#34;.
public enum CommentTextEntities {
    private nonisolated static let expression = try! NSRegularExpression(pattern: "&(#(?:[0-9]{1,10}|[xX][0-9a-fA-F]{1,8})|quot|apos|amp|lt|gt|nbsp);")

    public nonisolated static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let source = text as NSString
        var result = ""
        var end = 0
        for match in expression.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: end, length: match.range.location - end))
            let entity = source.substring(with: match.range(at: 1))
            let replacement: String?
            switch entity {
            case "quot": replacement = "\""
            case "apos": replacement = "'"
            case "amp": replacement = "&"
            case "lt": replacement = "<"
            case "gt": replacement = ">"
            case "nbsp": replacement = "\u{00A0}"
            default:
                let hexadecimal = entity.hasPrefix("#x") || entity.hasPrefix("#X")
                if let value = UInt32(entity.dropFirst(hexadecimal ? 2 : 1), radix: hexadecimal ? 16 : 10),
                   value > 0, let scalar = Unicode.Scalar(value) {
                    replacement = String(scalar)
                } else { replacement = nil }
            }
            result += replacement ?? source.substring(with: match.range)
            end = NSMaxRange(match.range)
        }
        result += source.substring(from: end)
        return result
    }
}

public struct CommentSubmission: Decodable {
    public let reply: Comment?
    public let successToast: String?
    public let needCaptcha: Bool?
    enum CodingKeys: String, CodingKey {
        case reply
        case successToast = "success_toast"
        case needCaptcha = "need_captcha"
    }
}

public enum CommentSubmissionError: LocalizedError {
    case verificationRequired
    public var errorDescription: String? { String(localized: "需要完成验证才能发送，请在官方客户端验证后重试。草稿已保留。") }
}
