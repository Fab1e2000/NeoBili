import Foundation
import Observation
import NeoBiliDomain

@MainActor @Observable
final class FavoriteFolderListModel {
    private let list = LibraryListState<FavMedia, Int>(firstCursor: 1)

    var videos: [FavMedia] { list.items }
    var hasMore: Bool { list.hasMore }
    var isLoading: Bool { list.isLoading }
    var isLoadingMore: Bool { list.isLoadingMore }
    var errorMessage: String? { list.errorMessage }
    var removals: ListRemovalState<Int> { list.removals }
    var entranceGeneration: Int { list.entranceGeneration }
    var contentRevision: Int { list.contentRevision }
    var isRemovingSelected: Bool { list.isRemovingBatch }
    var isSelecting: Bool {
        get { list.isSelecting }
        set { list.isSelecting = newValue }
    }
    var selectedIDs: Set<Int> {
        get { list.selectedIDs }
        set { list.selectedIDs = newValue }
    }

    func discardStagedPage() { list.discardStagedPage() }
    func reset() { list.reset() }

    func loadIfNeeded(services: ApplicationServices, folder: FavFolder) async {
        guard videos.isEmpty, !isLoading else { return }
        await reload(services: services, folder: folder)
    }

    func stageReload(services: ApplicationServices, feedback: ActionFeedback, folder: FavFolder) async -> Bool {
        await list.loadFirstPage(staged: true, fetch: { try await fetchPage($0, services: services, folder: folder) },
                                 onFailure: feedback.show)
    }

    func reload(services: ApplicationServices, folder: FavFolder) async {
        await list.loadFirstPage(staged: false) { try await fetchPage($0, services: services, folder: folder) }
    }

    func commitStagedReload() { list.commitStagedPage() }

    func loadMoreIfNeeded(services: ApplicationServices, folder: FavFolder, refreshing: Bool) async {
        guard !isSelecting, errorMessage == nil else { return }
        await loadNextPage(services: services, folder: folder, refreshing: refreshing)
    }

    func loadNextPage(services: ApplicationServices, folder: FavFolder, refreshing: Bool) async {
        guard !refreshing else { return }
        await list.loadNextPage { try await fetchPage($0, services: services, folder: folder) }
    }

    private func fetchPage(_ page: Int, services: ApplicationServices, folder: FavFolder) async throws -> LibraryListState<FavMedia, Int>.Page {
        let payload = try await services.library.favoriteVideos(folderID: folder.id, page: page)
        let rawItems = payload.medias ?? []
        return .init(items: rawItems.filter(\.isVideo), nextCursor: page + 1,
                     hasMore: LibraryPageRules.hasMoreFavorites(rawCount: rawItems.count))
    }

    func removeSelected(services: ApplicationServices, account: AccountStore, feedback: ActionFeedback, folder: FavFolder, refreshing: Bool) async {
        guard !refreshing else { return }
        let owner = account.sessionID
        let identitySession = services.session.currentID()
        if let error = await list.removeBatch(ids: selectedIDs, isCurrent: { account.sessionID == owner },
            confirm: { await feedback.confirmRemoval(String(localized: "已移出收藏夹")) },
            write: { try await services.library.removeFavorite(folderID: folder.id, aid: $0.id, expectedSessionID: identitySession) }) {
            feedback.show(error)
        }
    }

    func remove(_ media: FavMedia, services: ApplicationServices, account: AccountStore, feedback: ActionFeedback, folder: FavFolder, refreshing: Bool) async {
        guard !refreshing else { return }
        let owner = account.sessionID
        let identitySession = services.session.currentID()
        if let error = await list.remove(media, isCurrent: { account.sessionID == owner },
            confirm: { await feedback.confirmRemoval(String(localized: "已移出收藏夹")) },
            write: { try await services.library.removeFavorite(folderID: folder.id, aid: $0.id, expectedSessionID: identitySession) }) {
            feedback.show(error)
        }
    }
}
