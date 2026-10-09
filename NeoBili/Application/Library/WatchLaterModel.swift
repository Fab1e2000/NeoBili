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
    private(set) var items: [WatchLaterItem] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var hasMore = false
    private(set) var isRemoving = false
    private(set) var errorMessage: String?
    var selectedIDs: Set<Int> = []
    var isSelecting = false
    private var failedRefresh = false
    private var nextKey = ""
    private var splitKey = ""
    private var generation = UUID()
    private var owner: UUID?
    private let client: Client

    init(client: Client = .live) { self.client = client }

    func reset() {
        generation = UUID(); owner = nil
        items = []; selectedIDs = []; isSelecting = false
        isLoading = false; isRemoving = false; hasLoaded = false
        hasMore = false; nextKey = ""; splitKey = ""; errorMessage = nil; failedRefresh = false
    }

    func loadInitial() async {
        if owner != client.session() { reset() }
        if !hasLoaded { await load() }
    }

    func load(refresh: Bool = false) async {
        let session = client.session()
        if owner != session { reset(); owner = session }
        let refreshing = refresh || failedRefresh
        guard !isRemoving, !isLoading, refreshing || !hasLoaded || hasMore else { return }
        let request = UUID(); generation = request
        let key = refreshing ? "" : nextKey
        isLoading = true; errorMessage = nil
        defer { if generation == request { isLoading = false } }
        do {
            let page = try await client.load(key, refreshing ? "" : splitKey, session)
            guard generation == request, client.session() == session, !Task.isCancelled else { return }
            var seen = Set(refreshing ? [] : items.map(\.id))
            let incoming = page.items.filter { $0.bvid?.isEmpty == false && seen.insert($0.id).inserted }
            if refreshing { items = incoming } else { items += incoming }
            selectedIDs.formIntersection(Set(items.map(\.id)))
            hasLoaded = true; failedRefresh = false
            // A repeated/empty cursor must never create an endless request loop.
            hasMore = page.hasMore && !page.nextKey.isEmpty && page.nextKey != key
            nextKey = page.nextKey; splitKey = page.splitKey
        } catch {
            guard generation == request, client.session() == session, !error.isCancellation else { return }
            failedRefresh = refreshing
            errorMessage = error.localizedDescription
        }
    }

    func toggle(_ item: WatchLaterItem) {
        guard !isRemoving, item.aid != nil else { return }
        if selectedIDs.contains(item.id) { selectedIDs.remove(item.id) } else { selectedIDs.insert(item.id) }
    }

    /// Individual confirmed deletes allow accurate rollback when only some writes succeed.
    func remove(ids: Set<Int>, confirm: @MainActor () async -> Bool) async -> String? {
        guard !isRemoving, !isLoading else { return nil }
        let session = client.session()
        guard owner == session else { return nil }
        let snapshot = items
        let targets = snapshot.filter { ids.contains($0.id) && $0.aid != nil }
        guard !targets.isEmpty else { return nil }
        let request = UUID(); generation = request; isRemoving = true
        let targetIDs = Set(targets.map(\.id))
        items.removeAll { targetIDs.contains($0.id) }
        var succeeded: Set<Int> = []
        var failure: String?
        if await confirm(), !Task.isCancelled, client.session() == session {
            for item in targets {
                guard !Task.isCancelled, client.session() == session else { break }
                do { try await client.remove(item.aid!, session); succeeded.insert(item.id) }
                catch { if !error.isCancellation { failure = error.localizedDescription } }
            }
        }
        guard generation == request, client.session() == session else { return nil }
        items = snapshot.filter { !succeeded.contains($0.id) }
        selectedIDs.subtract(succeeded)
        isRemoving = false
        if selectedIDs.isEmpty { isSelecting = false }
        return failure
    }
}
