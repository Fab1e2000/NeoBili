import Foundation

/// Library operations available to application state and views.
/// Values can be replaced per model or view hierarchy without changing global state.
struct LibraryService: Sendable {
    var historyPageOperation: @Sendable (Int, Int) async throws -> HistoryCursorPage = { _, _ in throw ServiceError.unconfigured("Library.historyPage") }
    var reportWatchProgressOperation: @Sendable (String, Int, Double, UUID) async throws -> Void = { _, _, _, _ in throw ServiceError.unconfigured("Library.reportWatchProgress") }
    var deleteHistoryOperation: @Sendable (String, UUID?) async throws -> Void = { _, _ in throw ServiceError.unconfigured("Library.deleteHistory") }
    var reportAppWatchOperation: @Sendable (String, Int, Int, PlaybackWatchReport, UUID) async throws -> Int? = { _, _, _, _, _ in throw ServiceError.unconfigured("Library.reportAppWatch") }
    var favoriteFoldersOperation: @Sendable (Int, Int?) async throws -> [FavFolder] = { _, _ in throw ServiceError.unconfigured("Library.favoriteFolders") }
    var favoriteVideosOperation: @Sendable (Int, Int) async throws -> FavResourceList = { _, _ in throw ServiceError.unconfigured("Library.favoriteVideos") }
    var removeFavoriteOperation: @Sendable (Int, Int, UUID?) async throws -> Void = { _, _, _ in throw ServiceError.unconfigured("Library.removeFavorite") }
    var unfavoriteEverywhereOperation: @Sendable (Int) async throws -> Void = { _ in throw ServiceError.unconfigured("Library.unfavoriteEverywhere") }
    var deleteFavoriteFoldersOperation: @Sendable ([Int], UUID?) async throws -> Void = { _, _ in throw ServiceError.unconfigured("Library.deleteFavoriteFolders") }
    var addWatchLaterOperation: @Sendable (Int?, String?) async throws -> Void = { _, _ in throw ServiceError.unconfigured("Library.addWatchLater") }
    var watchLaterPageOperation: @Sendable (String, String, UUID) async throws -> WatchLaterListPage = { _, _, _ in throw ServiceError.unconfigured("Library.watchLaterPage") }
    var removeWatchLaterOperation: @Sendable (Int, UUID?) async throws -> Void = { _, _ in throw ServiceError.unconfigured("Library.removeWatchLater") }

    func historyPage(max: Int, viewAt: Int) async throws -> HistoryCursorPage {
        try await historyPageOperation(max, viewAt)
    }

    func reportWatchProgress(bvid: String, cid: Int, playedTime: Double, expectedSessionID: UUID) async throws {
        try await reportWatchProgressOperation(bvid, cid, playedTime, expectedSessionID)
    }

    func deleteHistory(kid: String, expectedSessionID: UUID? = nil) async throws {
        try await deleteHistoryOperation(kid, expectedSessionID)
    }

    func reportAppWatch(bvid: String, aid: Int, cid: Int, report: PlaybackWatchReport, expectedSessionID: UUID) async throws -> Int? {
        try await reportAppWatchOperation(bvid, aid, cid, report, expectedSessionID)
    }

    func favoriteFolders(ownerMid: Int, videoAid: Int? = nil) async throws -> [FavFolder] {
        try await favoriteFoldersOperation(ownerMid, videoAid)
    }

    func favoriteVideos(folderID: Int, page: Int) async throws -> FavResourceList {
        try await favoriteVideosOperation(folderID, page)
    }

    func removeFavorite(folderID: Int, aid: Int, expectedSessionID: UUID? = nil) async throws {
        try await removeFavoriteOperation(folderID, aid, expectedSessionID)
    }

    func unfavoriteEverywhere(aid: Int) async throws {
        try await unfavoriteEverywhereOperation(aid)
    }

    func deleteFavoriteFolders(folderIDs: [Int], expectedSessionID: UUID? = nil) async throws {
        try await deleteFavoriteFoldersOperation(folderIDs, expectedSessionID)
    }

    func addWatchLater(aid: Int?, bvid: String?) async throws {
        try await addWatchLaterOperation(aid, bvid)
    }

    func watchLaterPage(startKey: String, splitKey: String, expectedSessionID: UUID) async throws -> WatchLaterListPage {
        try await watchLaterPageOperation(startKey, splitKey, expectedSessionID)
    }

    func removeWatchLater(aid: Int, expectedSessionID: UUID? = nil) async throws {
        try await removeWatchLaterOperation(aid, expectedSessionID)
    }
}
