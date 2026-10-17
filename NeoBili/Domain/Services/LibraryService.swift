import Foundation

/// Library operations available to application state and views.
/// Values can be replaced per model or view hierarchy without changing global state.
public struct LibraryService: Sendable {
    public var historyPageOperation: @Sendable (Int, Int) async throws -> HistoryCursorPage = { _, _ in throw ServiceError.unconfigured("Library.historyPage") }
    public var reportWatchProgressOperation: @Sendable (String, Int, Double, UUID) async throws -> Void = { _, _, _, _ in throw ServiceError.unconfigured("Library.reportWatchProgress") }
    public var deleteHistoryOperation: @Sendable (String, UUID?) async throws -> Void = { _, _ in throw ServiceError.unconfigured("Library.deleteHistory") }
    public var reportAppWatchOperation: @Sendable (String, Int, Int, PlaybackWatchReport, UUID) async throws -> Int? = { _, _, _, _, _ in throw ServiceError.unconfigured("Library.reportAppWatch") }
    public var favoriteFoldersOperation: @Sendable (Int, Int?) async throws -> [FavFolder] = { _, _ in throw ServiceError.unconfigured("Library.favoriteFolders") }
    public var favoriteVideosOperation: @Sendable (Int, Int) async throws -> FavResourceList = { _, _ in throw ServiceError.unconfigured("Library.favoriteVideos") }
    public var removeFavoriteOperation: @Sendable (Int, Int, UUID?) async throws -> Void = { _, _, _ in throw ServiceError.unconfigured("Library.removeFavorite") }
    public var unfavoriteEverywhereOperation: @Sendable (Int) async throws -> Void = { _ in throw ServiceError.unconfigured("Library.unfavoriteEverywhere") }
    public var deleteFavoriteFoldersOperation: @Sendable ([Int], UUID?) async throws -> Void = { _, _ in throw ServiceError.unconfigured("Library.deleteFavoriteFolders") }
    public var addWatchLaterOperation: @Sendable (Int?, String?) async throws -> Void = { _, _ in throw ServiceError.unconfigured("Library.addWatchLater") }
    public var watchLaterPageOperation: @Sendable (String, String, UUID) async throws -> WatchLaterListPage = { _, _, _ in throw ServiceError.unconfigured("Library.watchLaterPage") }
    public var removeWatchLaterOperation: @Sendable (Int, UUID?) async throws -> Void = { _, _ in throw ServiceError.unconfigured("Library.removeWatchLater") }

    public func historyPage(max: Int, viewAt: Int) async throws -> HistoryCursorPage {
        try await historyPageOperation(max, viewAt)
    }

    public func reportWatchProgress(bvid: String, cid: Int, playedTime: Double, expectedSessionID: UUID) async throws {
        try await reportWatchProgressOperation(bvid, cid, playedTime, expectedSessionID)
    }

    public func deleteHistory(kid: String, expectedSessionID: UUID? = nil) async throws {
        try await deleteHistoryOperation(kid, expectedSessionID)
    }

    public func reportAppWatch(bvid: String, aid: Int, cid: Int, report: PlaybackWatchReport, expectedSessionID: UUID) async throws -> Int? {
        try await reportAppWatchOperation(bvid, aid, cid, report, expectedSessionID)
    }

    public func favoriteFolders(ownerMid: Int, videoAid: Int? = nil) async throws -> [FavFolder] {
        try await favoriteFoldersOperation(ownerMid, videoAid)
    }

    public func favoriteVideos(folderID: Int, page: Int) async throws -> FavResourceList {
        try await favoriteVideosOperation(folderID, page)
    }

    public func removeFavorite(folderID: Int, aid: Int, expectedSessionID: UUID? = nil) async throws {
        try await removeFavoriteOperation(folderID, aid, expectedSessionID)
    }

    public func unfavoriteEverywhere(aid: Int) async throws {
        try await unfavoriteEverywhereOperation(aid)
    }

    public func deleteFavoriteFolders(folderIDs: [Int], expectedSessionID: UUID? = nil) async throws {
        try await deleteFavoriteFoldersOperation(folderIDs, expectedSessionID)
    }

    public func addWatchLater(aid: Int?, bvid: String?) async throws {
        try await addWatchLaterOperation(aid, bvid)
    }

    public func watchLaterPage(startKey: String, splitKey: String, expectedSessionID: UUID) async throws -> WatchLaterListPage {
        try await watchLaterPageOperation(startKey, splitKey, expectedSessionID)
    }

    public func removeWatchLater(aid: Int, expectedSessionID: UUID? = nil) async throws {
        try await removeWatchLaterOperation(aid, expectedSessionID)
    }

    public init(
        historyPageOperation: @escaping @Sendable (Int, Int) async throws -> HistoryCursorPage = { _, _ in throw ServiceError.unconfigured("Library.historyPage") },
        reportWatchProgressOperation: @escaping @Sendable (String, Int, Double, UUID) async throws -> Void = { _, _, _, _ in throw ServiceError.unconfigured("Library.reportWatchProgress") },
        deleteHistoryOperation: @escaping @Sendable (String, UUID?) async throws -> Void = { _, _ in throw ServiceError.unconfigured("Library.deleteHistory") },
        reportAppWatchOperation: @escaping @Sendable (String, Int, Int, PlaybackWatchReport, UUID) async throws -> Int? = { _, _, _, _, _ in throw ServiceError.unconfigured("Library.reportAppWatch") },
        favoriteFoldersOperation: @escaping @Sendable (Int, Int?) async throws -> [FavFolder] = { _, _ in throw ServiceError.unconfigured("Library.favoriteFolders") },
        favoriteVideosOperation: @escaping @Sendable (Int, Int) async throws -> FavResourceList = { _, _ in throw ServiceError.unconfigured("Library.favoriteVideos") },
        removeFavoriteOperation: @escaping @Sendable (Int, Int, UUID?) async throws -> Void = { _, _, _ in throw ServiceError.unconfigured("Library.removeFavorite") },
        unfavoriteEverywhereOperation: @escaping @Sendable (Int) async throws -> Void = { _ in throw ServiceError.unconfigured("Library.unfavoriteEverywhere") },
        deleteFavoriteFoldersOperation: @escaping @Sendable ([Int], UUID?) async throws -> Void = { _, _ in throw ServiceError.unconfigured("Library.deleteFavoriteFolders") },
        addWatchLaterOperation: @escaping @Sendable (Int?, String?) async throws -> Void = { _, _ in throw ServiceError.unconfigured("Library.addWatchLater") },
        watchLaterPageOperation: @escaping @Sendable (String, String, UUID) async throws -> WatchLaterListPage = { _, _, _ in throw ServiceError.unconfigured("Library.watchLaterPage") },
        removeWatchLaterOperation: @escaping @Sendable (Int, UUID?) async throws -> Void = { _, _ in throw ServiceError.unconfigured("Library.removeWatchLater") }
    ) {
        self.historyPageOperation = historyPageOperation
        self.reportWatchProgressOperation = reportWatchProgressOperation
        self.deleteHistoryOperation = deleteHistoryOperation
        self.reportAppWatchOperation = reportAppWatchOperation
        self.favoriteFoldersOperation = favoriteFoldersOperation
        self.favoriteVideosOperation = favoriteVideosOperation
        self.removeFavoriteOperation = removeFavoriteOperation
        self.unfavoriteEverywhereOperation = unfavoriteEverywhereOperation
        self.deleteFavoriteFoldersOperation = deleteFavoriteFoldersOperation
        self.addWatchLaterOperation = addWatchLaterOperation
        self.watchLaterPageOperation = watchLaterPageOperation
        self.removeWatchLaterOperation = removeWatchLaterOperation
    }
}
