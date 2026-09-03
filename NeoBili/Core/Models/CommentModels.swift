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
    /// 接口自带的楼中楼预览，最多 3 条。这部分是跟着一级评论一起返回的，
    /// 显示它们不需要任何额外请求。
    let replies: [Comment]?

    var id: Int { rpid }

    var message: String { content.message }

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
