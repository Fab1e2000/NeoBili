import Foundation

extension CommentService {
    static func live(client: APIClient = .shared) -> Self {
        Self(
            shootDanmakuOperation: { cid, bvid, message, progress, mode in
                try await BiliAPI.shootDanmaku(cid: cid, bvid: bvid, message: message, progress: progress, mode: mode)
            },
            commentsOperation: { oid, type, page in
                try await BiliAPI.comments(oid: oid, type: type, page: page)
            },
            sendCommentOperation: { oid, type, message, root, parent in
                try await BiliAPI.sendComment(oid: oid, type: type, message: message, root: root, parent: parent)
            },
            commentRepliesOperation: { oid, type, rootId, page in
                try await BiliAPI.commentReplies(oid: oid, type: type, rootId: rootId, page: page)
            },
            likeCommentOperation: { oid, type, rpid, like in
                try await BiliAPI.likeComment(oid: oid, type: type, rpid: rpid, like: like)
            }
        )
    }
}
