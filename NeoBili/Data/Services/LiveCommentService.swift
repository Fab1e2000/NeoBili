#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation

extension CommentService {
    public static func live(client: APIClient, identity: DeviceIdentity) -> Self {
        Self(
            shootDanmakuOperation: { cid, bvid, message, progress, mode in
                try await BiliAPI.shootDanmaku(cid: cid, bvid: bvid, message: message, progress: progress, mode: mode, client: client, identity: identity)
            },
            commentsOperation: { oid, type, page, sort in
                try await BiliAPI.comments(oid: oid, type: type, page: page, sort: sort, client: client)
            },
            sendCommentOperation: { oid, type, message, root, parent in
                try await BiliAPI.sendComment(oid: oid, type: type, message: message, root: root, parent: parent, client: client, identity: identity)
            },
            commentRepliesOperation: { oid, type, rootId, page in
                try await BiliAPI.commentReplies(oid: oid, type: type, rootId: rootId, page: page, client: client)
            },
            deleteCommentOperation: { oid, type, rpid, session in
                try await BiliAPI.deleteComment(oid: oid, type: type, rpid: rpid, expectedSessionID: session, client: client, identity: identity)
            },
            likeCommentOperation: { oid, type, rpid, like in
                try await BiliAPI.likeComment(oid: oid, type: type, rpid: rpid, like: like, client: client, identity: identity)
            }
        )
    }
}
