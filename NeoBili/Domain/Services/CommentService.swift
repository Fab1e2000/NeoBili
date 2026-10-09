import Foundation

/// Comment operations available to application state and views.
/// Values can be replaced per model or view hierarchy without changing global state.
struct CommentService: Sendable {
    var shootDanmakuOperation: @Sendable (Int, String, String, TimeInterval, Int) async throws -> Int? = { _, _, _, _, _ in throw ServiceError.unconfigured("Comment.shootDanmaku") }
    var commentsOperation: @Sendable (Int, Int, Int) async throws -> CommentPage = { _, _, _ in throw ServiceError.unconfigured("Comment.comments") }
    var sendCommentOperation: @Sendable (Int, Int, String, Int, Int) async throws -> CommentSubmission = { _, _, _, _, _ in throw ServiceError.unconfigured("Comment.sendComment") }
    var commentRepliesOperation: @Sendable (Int, Int, Int, Int) async throws -> CommentReplyPage = { _, _, _, _ in throw ServiceError.unconfigured("Comment.commentReplies") }
    var likeCommentOperation: @Sendable (Int, Int, Int, Bool) async throws -> Void = { _, _, _, _ in throw ServiceError.unconfigured("Comment.likeComment") }

    func shootDanmaku(cid: Int, bvid: String, message: String, progress: TimeInterval, mode: Int) async throws -> Int? {
        try await shootDanmakuOperation(cid, bvid, message, progress, mode)
    }

    func comments(oid: Int, type: Int, page: Int) async throws -> CommentPage {
        try await commentsOperation(oid, type, page)
    }

    func sendComment(oid: Int, type: Int, message: String, root: Int, parent: Int) async throws -> CommentSubmission {
        try await sendCommentOperation(oid, type, message, root, parent)
    }

    func commentReplies(oid: Int, type: Int, rootId: Int, page: Int) async throws -> CommentReplyPage {
        try await commentRepliesOperation(oid, type, rootId, page)
    }

    func likeComment(oid: Int, type: Int, rpid: Int, like: Bool) async throws {
        try await likeCommentOperation(oid, type, rpid, like)
    }
}
