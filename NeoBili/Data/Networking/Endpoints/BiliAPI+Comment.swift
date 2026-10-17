#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation

extension BiliAPI {
    /// 评论列表。
    ///
    /// `oid` + `type` 一起定位一个评论区：视频传 av 号和 `type: 1`，动态传
    /// `comment_id_str` 和它自己的 `comment_type`（图文 11、纯文字 17）。
    /// `sort: 1` 是按点赞数排序，也就是网页端默认的「热门」。
    /// 每条一级评论会顺带返回最多 3 条楼中楼，展示它们不需要再发请求。
    static func comments(oid: Int, type: Int, page: Int, client: APIClient = .shared) async throws -> CommentPage {
        try await client.get(
            path: "x/v2/reply",
            params: [
                "type": String(type),
                "oid": String(oid),
                "pn": String(page),
                "ps": "20",
                "sort": "1"
            ]
        )
    }

    /// 展开某条评论下的全部回复（楼中楼）。`root` 传那条一级评论的 `rpid`。
    ///
    /// 和一级评论不同，这个接口对未登录用户没有条数限制，可以正常一页页翻。
    static func sendComment(oid: Int, type: Int, message: String, root: Int, parent: Int, client: APIClient = .shared, identity: DeviceIdentity = .shared) async throws -> CommentSubmission {
        let csrf = await identity.csrfToken ?? ""
        let result: CommentSubmission = try await client.post(path: "x/v2/reply/add", form: [
            "oid": String(oid), "type": String(type), "message": message,
            "root": String(root), "parent": String(parent), "plat": "1", "csrf": csrf
        ])
        guard result.needCaptcha != true else { throw CommentSubmissionError.verificationRequired }
        return result
    }

    static func commentReplies(oid: Int, type: Int, rootId: Int, page: Int, client: APIClient = .shared) async throws -> CommentReplyPage {
        try await client.get(
            path: "x/v2/reply/reply",
            params: [
                "type": String(type),
                "oid": String(oid),
                "root": String(rootId),
                "pn": String(page),
                "ps": "20"
            ],
            requiresWBI: true
        )
    }

    /// 给评论点赞 / 取消点赞。`oid` 和 `type` 的含义与拉取评论时相同。
    static func likeComment(oid: Int, type: Int, rpid: Int, like: Bool, client: APIClient = .shared, identity: DeviceIdentity = .shared) async throws {
        let csrf = await identity.csrfToken ?? ""
        try await client.post(
            path: "x/v2/reply/action",
            form: [
                "type": String(type),
                "oid": String(oid),
                "rpid": String(rpid),
                "action": like ? "1" : "0",
                "csrf": csrf
            ]
        )
    }
}
