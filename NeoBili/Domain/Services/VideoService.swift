import Foundation

/// Video operations available to application state and views.
/// Values can be replaced per model or view hierarchy without changing global state.
public struct VideoService: Sendable {
    public var storyboardOperation: @Sendable (String, Int) async throws -> VideoStoryboard = { _, _ in throw ServiceError.unconfigured("Video.storyboard") }
    public func storyboard(bvid: String, cid: Int) async throws -> VideoStoryboard { try await storyboardOperation(bvid, cid) }

    public var playURLOperation: @Sendable (String, Int, Int) async throws -> PlayURLData = { _, _, _ in throw ServiceError.unconfigured("Video.playURL") }
    public var videoDetailOperation: @Sendable (String) async throws -> VideoDetail = { _ in throw ServiceError.unconfigured("Video.videoDetail") }
    public var appRelatedPageOperation: @Sendable (String, Int, PlaybackEntry, String, UUID, Data?) async throws -> AppRelatedPage = { _, _, _, _, _, _ in throw ServiceError.unconfigured("Video.appRelatedPage") }
    public var videoTagsOperation: @Sendable (Int) async throws -> [VideoTag] = { _ in throw ServiceError.unconfigured("Video.videoTags") }
    public var videoRelationOperation: @Sendable (Int, String) async throws -> VideoRelation = { _, _ in throw ServiceError.unconfigured("Video.videoRelation") }
    public var memberCardOperation: @Sendable (Int) async throws -> MemberCard = { _ in throw ServiceError.unconfigured("Video.memberCard") }
    public var likeVideoOperation: @Sendable (Int, Bool) async throws -> Void = { _, _ in throw ServiceError.unconfigured("Video.likeVideo") }
    public var likeVideoWithContextOperation: @Sendable (Int, Bool, PlaybackEntry, UUID?) async throws -> Void = { _, _, _, _ in throw ServiceError.unconfigured("Video.likeVideo") }
    public var dislikeVideoOperation: @Sendable (Int, Bool, PlaybackEntry?, UUID?) async throws -> Void = { _, _, _, _ in throw ServiceError.unconfigured("Video.dislikeVideo") }
    public var tripleActionOperation: @Sendable (Int, PlaybackEntry, UUID?) async throws -> TripleResult = { _, _, _ in throw ServiceError.unconfigured("Video.tripleAction") }
    public var addCoinOperation: @Sendable (Int, Int, Bool, PlaybackEntry, UUID?) async throws -> Void = { _, _, _, _, _ in throw ServiceError.unconfigured("Video.addCoin") }
    public var updateFavoritesOperation: @Sendable (Int, [Int], [Int], UUID?) async throws -> Void = { _, _, _, _ in throw ServiceError.unconfigured("Video.updateFavorites") }
    public var blockUserOperation: @Sendable (Int) async throws -> Void = { _ in throw ServiceError.unconfigured("Video.blockUser") }
    public var modifyRelationOperation: @Sendable (Int, Bool) async throws -> Void = { _, _ in throw ServiceError.unconfigured("Video.modifyRelation") }

    public func playURL(bvid: String, cid: Int, quality: Int = 127) async throws -> PlayURLData {
        try await playURLOperation(bvid, cid, quality)
    }

    public func videoDetail(bvid: String) async throws -> VideoDetail {
        try await videoDetailOperation(bvid)
    }

    public func appRelatedPage(bvid: String, aid: Int = 0, entry: PlaybackEntry = .other, playbackSession: String, expectedSessionID: UUID, pagination: Data? = nil) async throws -> AppRelatedPage {
        try await appRelatedPageOperation(bvid, aid, entry, playbackSession, expectedSessionID, pagination)
    }

    public func videoTags(aid: Int) async throws -> [VideoTag] {
        try await videoTagsOperation(aid)
    }

    public func videoRelation(aid: Int, bvid: String) async throws -> VideoRelation {
        try await videoRelationOperation(aid, bvid)
    }

    public func memberCard(mid: Int) async throws -> MemberCard {
        try await memberCardOperation(mid)
    }

    public func likeVideo(aid: Int, like: Bool) async throws {
        try await likeVideoOperation(aid, like)
    }

    public func likeVideo(aid: Int, like: Bool, entry: PlaybackEntry, expectedSessionID: UUID? = nil) async throws {
        try await likeVideoWithContextOperation(aid, like, entry, expectedSessionID)
    }

    public func dislikeVideo(aid: Int, dislike: Bool, entry: PlaybackEntry? = nil, expectedSessionID: UUID? = nil) async throws {
        try await dislikeVideoOperation(aid, dislike, entry, expectedSessionID)
    }

    public func tripleAction(aid: Int, entry: PlaybackEntry = .other, expectedSessionID: UUID? = nil) async throws -> TripleResult {
        try await tripleActionOperation(aid, entry, expectedSessionID)
    }

    public func addCoin(aid: Int, multiply: Int, selectLike: Bool = false, entry: PlaybackEntry = .other, expectedSessionID: UUID? = nil) async throws {
        try await addCoinOperation(aid, multiply, selectLike, entry, expectedSessionID)
    }

    public func updateFavorites(aid: Int, addFolderIDs: [Int], removeFolderIDs: [Int], expectedSessionID: UUID? = nil) async throws {
        try await updateFavoritesOperation(aid, addFolderIDs, removeFolderIDs, expectedSessionID)
    }

    public func blockUser(mid: Int) async throws {
        try await blockUserOperation(mid)
    }

    public func modifyRelation(mid: Int, follow: Bool) async throws {
        try await modifyRelationOperation(mid, follow)
    }

    public init(
        storyboardOperation: @escaping @Sendable (String, Int) async throws -> VideoStoryboard = { _, _ in throw ServiceError.unconfigured("Video.storyboard") },
        playURLOperation: @escaping @Sendable (String, Int, Int) async throws -> PlayURLData = { _, _, _ in throw ServiceError.unconfigured("Video.playURL") },
        videoDetailOperation: @escaping @Sendable (String) async throws -> VideoDetail = { _ in throw ServiceError.unconfigured("Video.videoDetail") },
        appRelatedPageOperation: @escaping @Sendable (String, Int, PlaybackEntry, String, UUID, Data?) async throws -> AppRelatedPage = { _, _, _, _, _, _ in throw ServiceError.unconfigured("Video.appRelatedPage") },
        videoTagsOperation: @escaping @Sendable (Int) async throws -> [VideoTag] = { _ in throw ServiceError.unconfigured("Video.videoTags") },
        videoRelationOperation: @escaping @Sendable (Int, String) async throws -> VideoRelation = { _, _ in throw ServiceError.unconfigured("Video.videoRelation") },
        memberCardOperation: @escaping @Sendable (Int) async throws -> MemberCard = { _ in throw ServiceError.unconfigured("Video.memberCard") },
        likeVideoOperation: @escaping @Sendable (Int, Bool) async throws -> Void = { _, _ in throw ServiceError.unconfigured("Video.likeVideo") },
        likeVideoWithContextOperation: @escaping @Sendable (Int, Bool, PlaybackEntry, UUID?) async throws -> Void = { _, _, _, _ in throw ServiceError.unconfigured("Video.likeVideo") },
        dislikeVideoOperation: @escaping @Sendable (Int, Bool, PlaybackEntry?, UUID?) async throws -> Void = { _, _, _, _ in throw ServiceError.unconfigured("Video.dislikeVideo") },
        tripleActionOperation: @escaping @Sendable (Int, PlaybackEntry, UUID?) async throws -> TripleResult = { _, _, _ in throw ServiceError.unconfigured("Video.tripleAction") },
        addCoinOperation: @escaping @Sendable (Int, Int, Bool, PlaybackEntry, UUID?) async throws -> Void = { _, _, _, _, _ in throw ServiceError.unconfigured("Video.addCoin") },
        updateFavoritesOperation: @escaping @Sendable (Int, [Int], [Int], UUID?) async throws -> Void = { _, _, _, _ in throw ServiceError.unconfigured("Video.updateFavorites") },
        blockUserOperation: @escaping @Sendable (Int) async throws -> Void = { _ in throw ServiceError.unconfigured("Video.blockUser") },
        modifyRelationOperation: @escaping @Sendable (Int, Bool) async throws -> Void = { _, _ in throw ServiceError.unconfigured("Video.modifyRelation") }
    ) {
        self.storyboardOperation = storyboardOperation
        self.playURLOperation = playURLOperation
        self.videoDetailOperation = videoDetailOperation
        self.appRelatedPageOperation = appRelatedPageOperation
        self.videoTagsOperation = videoTagsOperation
        self.videoRelationOperation = videoRelationOperation
        self.memberCardOperation = memberCardOperation
        self.likeVideoOperation = likeVideoOperation
        self.likeVideoWithContextOperation = likeVideoWithContextOperation
        self.dislikeVideoOperation = dislikeVideoOperation
        self.tripleActionOperation = tripleActionOperation
        self.addCoinOperation = addCoinOperation
        self.updateFavoritesOperation = updateFavoritesOperation
        self.blockUserOperation = blockUserOperation
        self.modifyRelationOperation = modifyRelationOperation
    }
}
