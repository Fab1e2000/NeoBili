import Foundation
import Observation
import NeoBiliDomain

@MainActor @Observable
final class HistoryListModel {
    private typealias Cursor = (max: Int, viewAt: Int)
    private let list = LibraryListState<HistoryItem, Cursor>(firstCursor: (0, 0))

    var items: [HistoryItem] { list.items }
    var hasMore: Bool { list.hasMore }
    var isLoading: Bool { list.isLoading }
    var isLoadingMore: Bool { list.isLoadingMore }
    var errorMessage: String? { list.errorMessage }
    var removals: ListRemovalState<String> { list.removals }
    var entranceGeneration: Int { list.entranceGeneration }
    var contentRevision: Int { list.contentRevision }
    var isRemovingSelected: Bool { list.isRemovingBatch }
    var isSelecting: Bool {
        get { list.isSelecting }
        set { list.isSelecting = newValue }
    }
    var selectedIDs: Set<String> {
        get { list.selectedIDs }
        set { list.selectedIDs = newValue }
    }

    func discardStagedPage() { list.discardStagedPage() }
    func reset() { list.reset() }

    func loadIfNeeded(services: ApplicationServices) async {
        guard items.isEmpty, !isLoading else { return }
        await reload(services: services)
    }

    func stageReload(services: ApplicationServices, feedback: ActionFeedback) async -> Bool {
        await list.loadFirstPage(staged: true, fetch: { try await fetchPage($0, services: services) }, onFailure: feedback.show)
    }

    func reload(services: ApplicationServices) async {
        await list.loadFirstPage(staged: false) { try await fetchPage($0, services: services) }
    }

    func commitStagedReload() { list.commitStagedPage() }

    func loadMoreIfNeeded(services: ApplicationServices, refreshing: Bool) async {
        guard !isSelecting, errorMessage == nil else { return }
        await loadNextPage(services: services, refreshing: refreshing)
    }

    func loadNextPage(services: ApplicationServices, refreshing: Bool) async {
        guard !refreshing else { return }
        await list.loadNextPage { try await fetchPage($0, services: services) }
    }

    private func fetchPage(_ cursor: Cursor, services: ApplicationServices) async throws -> LibraryListState<HistoryItem, Cursor>.Page {
        let payload = try await services.library.historyPage(max: cursor.max, viewAt: cursor.viewAt)
        return .init(
            items: payload.allItems.filter(\.isVideo),
            nextCursor: (payload.cursor?.max ?? 0, payload.cursor?.resolvedViewAt ?? 0),
            hasMore: LibraryPageRules.advancesHistory(max: payload.cursor?.max,
                viewAt: payload.cursor?.resolvedViewAt, fromMax: cursor.max, fromViewAt: cursor.viewAt))
    }

    func removeSelected(services: ApplicationServices, account: AccountStore, feedback: ActionFeedback, refreshing: Bool) async {
        guard !refreshing else { return }
        let owner = account.sessionID
        let identitySession = services.session.currentID()
        if let error = await list.removeBatch(ids: selectedIDs, isCurrent: { account.sessionID == owner },
            confirm: { await feedback.confirmRemoval(String(localized: "已移除历史记录")) },
            write: { try await services.library.deleteHistory(kid: $0.kidParam, expectedSessionID: identitySession) }) {
            feedback.show(error)
        }
    }

    func delete(_ item: HistoryItem, services: ApplicationServices, account: AccountStore, feedback: ActionFeedback, refreshing: Bool) async {
        guard !refreshing else { return }
        let owner = account.sessionID
        let identitySession = services.session.currentID()
        if let error = await list.remove(item, isCurrent: { account.sessionID == owner },
            confirm: { await feedback.confirmRemoval(String(localized: "已移除历史记录")) },
            write: { try await services.library.deleteHistory(kid: $0.kidParam, expectedSessionID: identitySession) }) {
            feedback.show(error)
        }
    }
}
