import Foundation

/// Video operations available to application state and views.
/// Values can be replaced per model or view hierarchy without changing global state.
struct VideoService: Sendable {
    var storyboardOperation: @Sendable (String, Int) async throws -> VideoStoryboard = { _, _ in throw ServiceError.unconfigured("Video.storyboard") }
    func storyboard(bvid: String, cid: Int) async throws -> VideoStoryboard { try await storyboardOperation(bvid, cid) }

    var playURLOperation: @Sendable (String, Int, Int) async throws -> PlayURLData = { _, _, _ in throw ServiceError.unconfigured("Video.playURL") }
    var videoDetailOperation: @Sendable (String) async throws -> VideoDetail = { _ in throw ServiceError.unconfigured("Video.videoDetail") }
    var appRelatedPageOperation: @Sendable (String, Int, PlaybackEntry, String, UUID, Data?) async throws -> AppRelatedPage = { _, _, _, _, _, _ in throw ServiceError.unconfigured("Video.appRelatedPage") }
    var videoTagsOperation: @Sendable (Int) async throws -> [VideoTag] = { _ in throw ServiceError.unconfigured("Video.videoTags") }
    var videoRelationOperation: @Sendable (Int, String) async throws -> VideoRelation = { _, _ in throw ServiceError.unconfigured("Video.videoRelation") }
    var memberCardOperation: @Sendable (Int) async throws -> MemberCard = { _ in throw ServiceError.unconfigured("Video.memberCard") }
    var likeVideoOperation: @Sendable (Int, Bool) async throws -> Void = { _, _ in throw ServiceError.unconfigured("Video.likeVideo") }
    var likeVideoWithContextOperation: @Sendable (Int, Bool, PlaybackEntry, UUID?) async throws -> Void = { _, _, _, _ in throw ServiceError.unconfigured("Video.likeVideo") }
    var dislikeVideoOperation: @Sendable (Int, Bool, PlaybackEntry?, UUID?) async throws -> Void = { _, _, _, _ in throw ServiceError.unconfigured("Video.dislikeVideo") }
    var tripleActionOperation: @Sendable (Int, PlaybackEntry, UUID?) async throws -> TripleResult = { _, _, _ in throw ServiceError.unconfigured("Video.tripleAction") }
    var addCoinOperation: @Sendable (Int, Int, Bool, PlaybackEntry, UUID?) async throws -> Void = { _, _, _, _, _ in throw ServiceError.unconfigured("Video.addCoin") }
    var updateFavoritesOperation: @Sendable (Int, [Int], [Int], UUID?) async throws -> Void = { _, _, _, _ in throw ServiceError.unconfigured("Video.updateFavorites") }
    var blockUserOperation: @Sendable (Int) async throws -> Void = { _ in throw ServiceError.unconfigured("Video.blockUser") }
    var modifyRelationOperation: @Sendable (Int, Bool) async throws -> Void = { _, _ in throw ServiceError.unconfigured("Video.modifyRelation") }

    func playURL(bvid: String, cid: Int, quality: Int = 127) async throws -> PlayURLData {
        try await playURLOperation(bvid, cid, quality)
    }

    func videoDetail(bvid: String) async throws -> VideoDetail {
        try await videoDetailOperation(bvid)
    }

    func appRelatedPage(bvid: String, aid: Int = 0, entry: PlaybackEntry = .other, playbackSession: String, expectedSessionID: UUID, pagination: Data? = nil) async throws -> AppRelatedPage {
        try await appRelatedPageOperation(bvid, aid, entry, playbackSession, expectedSessionID, pagination)
    }

    func videoTags(aid: Int) async throws -> [VideoTag] {
        try await videoTagsOperation(aid)
    }

    func videoRelation(aid: Int, bvid: String) async throws -> VideoRelation {
        try await videoRelationOperation(aid, bvid)
    }

    func memberCard(mid: Int) async throws -> MemberCard {
        try await memberCardOperation(mid)
    }

    func likeVideo(aid: Int, like: Bool) async throws {
        try await likeVideoOperation(aid, like)
    }

    func likeVideo(aid: Int, like: Bool, entry: PlaybackEntry, expectedSessionID: UUID? = nil) async throws {
        try await likeVideoWithContextOperation(aid, like, entry, expectedSessionID)
    }

    func dislikeVideo(aid: Int, dislike: Bool, entry: PlaybackEntry? = nil, expectedSessionID: UUID? = nil) async throws {
        try await dislikeVideoOperation(aid, dislike, entry, expectedSessionID)
    }

    func tripleAction(aid: Int, entry: PlaybackEntry = .other, expectedSessionID: UUID? = nil) async throws -> TripleResult {
        try await tripleActionOperation(aid, entry, expectedSessionID)
    }

    func addCoin(aid: Int, multiply: Int, selectLike: Bool = false, entry: PlaybackEntry = .other, expectedSessionID: UUID? = nil) async throws {
        try await addCoinOperation(aid, multiply, selectLike, entry, expectedSessionID)
    }

    func updateFavorites(aid: Int, addFolderIDs: [Int], removeFolderIDs: [Int], expectedSessionID: UUID? = nil) async throws {
        try await updateFavoritesOperation(aid, addFolderIDs, removeFolderIDs, expectedSessionID)
    }

    func blockUser(mid: Int) async throws {
        try await blockUserOperation(mid)
    }

    func modifyRelation(mid: Int, follow: Bool) async throws {
        try await modifyRelationOperation(mid, follow)
    }
}
