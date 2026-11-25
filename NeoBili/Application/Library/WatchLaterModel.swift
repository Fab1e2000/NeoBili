import NeoBiliDomain
import Foundation
import Observation

/// Account-bound list state. Only explicit selected records are removed; undo happens before HTTP.
@MainActor @Observable
final class WatchLaterModel {
    typealias Page = WatchLaterListPage
    struct Client {
        var load: @MainActor (String, String, UUID) async throws -> Page
        var remove: @MainActor (Int, UUID) async throws -> Void
        var session: @MainActor () -> UUID
        static var live: Self { .init(load: { next, split, session in
            try await ApplicationServices.live.library.watchLaterPage(startKey: next, splitKey: split, expectedSessionID: session)
        }, remove: { aid, session in
            try await ApplicationServices.live.library.removeWatchLater(aid: aid, expectedSessionID: session)
        }, session: { ApplicationServices.live.session.currentID() }) }
    }
    private typealias Cursor = (nextKey: String, splitKey: String)
    private let list = LibraryListState<WatchLaterItem, Cursor>(firstCursor: ("", ""), hasMore: false)
    private var owner: UUID?
    private let client: Client

    var items: [WatchLaterItem] { list.items }
    var isLoading: Bool { list.isLoading || list.isLoadingMore }
    var hasLoaded: Bool { list.hasLoaded }
    var hasMore: Bool { list.hasMore }
    var isRemoving: Bool { list.isRemovingBatch }
    var errorMessage: String? { list.errorMessage }
    var entranceGeneration: Int { list.entranceGeneration }
    var contentRevision: Int { list.contentRevision }
    var selectedIDs: Set<Int> {
        get { list.selectedIDs }
        set { list.selectedIDs = newValue }
    }
    var isSelecting: Bool {
        get { list.isSelecting }
        set { list.isSelecting = newValue }
    }
    private(set) var failedRefresh = false

    init(client: Client = .live) { self.client = client }

    func reset() {
        list.reset(hasMore: false)
        owner = nil
        failedRefresh = false
    }

    func loadInitial() async {
        if owner != client.session() { reset() }
        if !hasLoaded { await load() }
    }

    func load(refresh: Bool = false) async {
        let session = currentSession()
        guard !isRemoving, !isLoading else { return }
        let refreshing = refresh || failedRefresh
        if refreshing || !hasLoaded {
            if await loadFirstPage(staged: false, refreshing: refreshing, session: session),
               ownsList(session) {
                failedRefresh = false
            }
        } else {
            await list.loadNextPage(isCurrent: { ownsList(session) }, prunesSelection: true) {
                try await fetchPage($0, session: session)
            }
        }
    }

    /// Keep the old rows until the page finishes its exit animation.
    func stageRefresh() async -> Bool {
        let session = currentSession()
        guard !isRemoving, !isLoading else { return false }
        return await loadFirstPage(staged: true, refreshing: true, session: session)
    }

    func commitStagedRefresh() {
        guard owner == client.session(), !isRemoving else {
            discardStagedRefresh()
            return
        }
        if list.commitStagedPage() { failedRefresh = false }
    }

    func discardStagedRefresh() { list.discardStagedPage() }

    private func loadFirstPage(staged: Bool, refreshing: Bool, session: UUID) async -> Bool {
        list.errorMessage = nil
        return await list.loadFirstPage(staged: staged, isCurrent: { ownsList(session) }, exitsEmptySelection: false,
            fetch: { try await fetchPage($0, session: session) },
            onFailure: { [self] message in
                failedRefresh = refreshing
                list.errorMessage = message
            })
    }

    private func fetchPage(_ cursor: Cursor, session: UUID) async throws -> LibraryListState<WatchLaterItem, Cursor>.Page {
        let page = try await client.load(cursor.nextKey, cursor.splitKey, session)
        return .init(items: page.items.filter { $0.bvid?.isEmpty == false },
                     nextCursor: (page.nextKey, page.splitKey),
                     hasMore: page.hasMore && !page.nextKey.isEmpty && page.nextKey != cursor.nextKey)
    }

    private func ownsList(_ session: UUID) -> Bool {
        owner == session && client.session() == session
    }

    private func currentSession() -> UUID {
        let session = client.session()
        if owner != session {
            reset()
            owner = session
        }
        return session
    }

    func toggle(_ item: WatchLaterItem) {
        guard !isRemoving, item.aid != nil else { return }
        if selectedIDs.contains(item.id) { selectedIDs.remove(item.id) } else { selectedIDs.insert(item.id) }
    }

    func remove(ids: Set<Int>, confirm: @MainActor () async -> Bool) async -> String? {
        let session = client.session()
        guard owner == session else { return nil }
        return await list.removeBatch(ids: ids, canRemove: { $0.aid != nil },
            isCurrent: { ownsList(session) }, confirm: confirm,
            write: { try await client.remove($0.id, session) })
    }
}
