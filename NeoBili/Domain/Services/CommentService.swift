import Foundation

/// Comment operations available to application state and views.
/// Values can be replaced per model or view hierarchy without changing global state.
public struct CommentService: Sendable {
    public var shootDanmakuOperation: @Sendable (Int, String, String, TimeInterval, Int) async throws -> Int? = { _, _, _, _, _ in throw ServiceError.unconfigured("Comment.shootDanmaku") }
    public var commentsOperation: @Sendable (Int, Int, Int, CommentSort) async throws -> CommentPage = { _, _, _, _ in throw ServiceError.unconfigured("Comment.comments") }
    public var sendCommentOperation: @Sendable (Int, Int, String, Int, Int) async throws -> CommentSubmission = { _, _, _, _, _ in throw ServiceError.unconfigured("Comment.sendComment") }
    public var commentRepliesOperation: @Sendable (Int, Int, Int, Int) async throws -> CommentReplyPage = { _, _, _, _ in throw ServiceError.unconfigured("Comment.commentReplies") }
    public var likeCommentOperation: @Sendable (Int, Int, Int, Bool) async throws -> Void = { _, _, _, _ in throw ServiceError.unconfigured("Comment.likeComment") }

    public var deleteCommentOperation: @Sendable (Int, Int, Int, UUID) async throws -> Void = { _, _, _, _ in throw ServiceError.unconfigured("Comment.deleteComment") }

    public func deleteComment(oid: Int, type: Int, rpid: Int, expectedSessionID: UUID) async throws {
        try await deleteCommentOperation(oid, type, rpid, expectedSessionID)
    }

    public func shootDanmaku(cid: Int, bvid: String, message: String, progress: TimeInterval, mode: Int) async throws -> Int? {
        try await shootDanmakuOperation(cid, bvid, message, progress, mode)
    }

    public func comments(oid: Int, type: Int, page: Int, sort: CommentSort = .hot) async throws -> CommentPage {
        try await commentsOperation(oid, type, page, sort)
    }

    public func sendComment(oid: Int, type: Int, message: String, root: Int, parent: Int) async throws -> CommentSubmission {
        try await sendCommentOperation(oid, type, message, root, parent)
    }

    public func commentReplies(oid: Int, type: Int, rootId: Int, page: Int) async throws -> CommentReplyPage {
        try await commentRepliesOperation(oid, type, rootId, page)
    }

    public func likeComment(oid: Int, type: Int, rpid: Int, like: Bool) async throws {
        try await likeCommentOperation(oid, type, rpid, like)
    }

    public init(
        shootDanmakuOperation: @escaping @Sendable (Int, String, String, TimeInterval, Int) async throws -> Int? = { _, _, _, _, _ in throw ServiceError.unconfigured("Comment.shootDanmaku") },
        commentsOperation: @escaping @Sendable (Int, Int, Int, CommentSort) async throws -> CommentPage = { _, _, _, _ in throw ServiceError.unconfigured("Comment.comments") },
        sendCommentOperation: @escaping @Sendable (Int, Int, String, Int, Int) async throws -> CommentSubmission = { _, _, _, _, _ in throw ServiceError.unconfigured("Comment.sendComment") },
        commentRepliesOperation: @escaping @Sendable (Int, Int, Int, Int) async throws -> CommentReplyPage = { _, _, _, _ in throw ServiceError.unconfigured("Comment.commentReplies") },
        deleteCommentOperation: @escaping @Sendable (Int, Int, Int, UUID) async throws -> Void = { _, _, _, _ in throw ServiceError.unconfigured("Comment.deleteComment") },
        likeCommentOperation: @escaping @Sendable (Int, Int, Int, Bool) async throws -> Void = { _, _, _, _ in throw ServiceError.unconfigured("Comment.likeComment") }
    ) {
        self.shootDanmakuOperation = shootDanmakuOperation
        self.commentsOperation = commentsOperation
        self.sendCommentOperation = sendCommentOperation
        self.commentRepliesOperation = commentRepliesOperation
        self.deleteCommentOperation = deleteCommentOperation
        self.likeCommentOperation = likeCommentOperation
    }
}
