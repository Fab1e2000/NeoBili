import Foundation
import Observation

/// Coordinates list updates while each model translates its own page and cursor.
@MainActor @Observable
final class LibraryListState<Item: Identifiable, Cursor> where Item.ID: Sendable {
    struct Page {
        let items: [Item]
        let nextCursor: Cursor
        let hasMore: Bool
    }

    private let firstCursor: Cursor
    private var cursor: Cursor
    private var stagedPage: Page?
    private var loadID = UUID()

    private(set) var items: [Item] = []
    private(set) var hasLoaded = false
    private(set) var hasMore: Bool
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var isRemovingBatch = false
    private(set) var removals = ListRemovalState<Item.ID>()
    var errorMessage: String?
    var isSelecting = false
    var selectedIDs: Set<Item.ID> = []
    /// A first-page replacement restarts card entrance animations.
    private(set) var entranceGeneration = 0
    /// Row changes invalidate the view's filtering cache.
    private(set) var contentRevision = 0

    init(firstCursor: Cursor, hasMore: Bool = true) {
        self.firstCursor = firstCursor
        cursor = firstCursor
        self.hasMore = hasMore
    }

    func reset(hasMore: Bool = true) {
        loadID = UUID()
        stagedPage = nil
        cursor = firstCursor
        items = []
        selectedIDs = []
        isSelecting = false
        contentRevision += 1
        isLoading = false
        isLoadingMore = false
        isRemovingBatch = false
        removals = ListRemovalState()
        hasLoaded = false
        self.hasMore = hasMore
        errorMessage = nil
    }

    func discardStagedPage() { stagedPage = nil }

    @discardableResult
    func loadFirstPage(
        staged: Bool, isCurrent: () -> Bool = { true }, exitsEmptySelection: Bool = true,
        fetch: @MainActor (Cursor) async throws -> Page, onFailure: ((String) -> Void)? = nil
    ) async -> Bool {
        guard !removals.hasPending else { return false }
        discardStagedPage()
        return await loadPage(from: firstCursor, loadingMore: false, isCurrent: isCurrent, fetch: fetch) { page in
            stagedPage = page
            if !staged { commitStagedPage(exitsEmptySelection: exitsEmptySelection) }
        } onFailure: { message in
            if let onFailure { onFailure(message) }
            else if items.isEmpty { errorMessage = message }
        }
    }

    @discardableResult
    func commitStagedPage(exitsEmptySelection: Bool = true) -> Bool {
        guard let page = stagedPage else { return false }
        discardStagedPage()
        items = LibraryPageRules.unique(page.items)
        entranceGeneration += 1
        selectedIDs.formIntersection(Set(items.map(\.id)))
        if exitsEmptySelection, selectedIDs.isEmpty { isSelecting = false }
        applyPageMetadata(page)
        return true
    }

    func loadNextPage(
        isCurrent: () -> Bool = { true }, prunesSelection: Bool = false,
        fetch: @MainActor (Cursor) async throws -> Page
    ) async {
        guard !removals.hasPending, stagedPage == nil, hasMore, !isLoading, !isLoadingMore else { return }
        errorMessage = nil
        await loadPage(from: cursor, loadingMore: !items.isEmpty, isCurrent: isCurrent, fetch: fetch) { page in
            items.append(contentsOf: LibraryPageRules.unique(page.items, excluding: Set(items.map(\.id))))
            if prunesSelection { selectedIDs.formIntersection(Set(items.map(\.id))) }
            applyPageMetadata(page)
        } onFailure: { errorMessage = $0 }
    }

    @discardableResult
    private func loadPage(
        from cursor: Cursor, loadingMore: Bool, isCurrent: () -> Bool,
        fetch: @MainActor (Cursor) async throws -> Page, apply: (Page) -> Void, onFailure: (String) -> Void
    ) async -> Bool {
        let request = UUID()
        // A removal invalidates a page even if its undo or rollback has already finished.
        let revision = removals.revision
        loadID = request
        isLoading = !loadingMore
        isLoadingMore = loadingMore
        defer {
            if loadID == request {
                isLoading = false
                isLoadingMore = false
            }
        }
        do {
            let page = try await fetch(cursor)
            guard loadID == request, removals.revision == revision, isCurrent(), !Task.isCancelled else { return false }
            apply(page)
            return true
        } catch {
            guard loadID == request, removals.revision == revision, isCurrent(), !error.isCancellation else { return false }
            onFailure(error.loadFailureDescription)
            return false
        }
    }

    private func applyPageMetadata(_ page: Page) {
        cursor = page.nextCursor
        hasMore = page.hasMore
        hasLoaded = true
        contentRevision += 1
        errorMessage = nil
    }

    func remove(
        _ item: Item, isCurrent: @MainActor () -> Bool, confirm: @MainActor () async -> Bool,
        write: @MainActor (Item) async throws -> Void
    ) async -> String? {
        let removals = removals
        guard !isRemovingBatch, items.contains(where: { $0.id == item.id }), removals.begin(item.id) else { return nil }
        discardStagedPage()
        removals.hide(item.id)
        let index = removals.remove(item.id, from: &items)
        contentRevision += 1
        let result = await LibraryBatchRemoval.perform(ids: [item.id],
            isCurrent: { self.removals === removals && isCurrent() }, confirm: confirm, remove: { _ in try await write(item) })
        guard self.removals === removals, isCurrent() else { return nil }
        if result.succeeded.isEmpty, let index {
            removals.restore(item, at: index, in: &items)
            contentRevision += 1
        } else {
            finishRemoval(of: result.succeeded)
        }
        removals.finish(item.id)
        return result.error
    }

    func removeBatch(
        ids: Set<Item.ID>, canRemove: (Item) -> Bool = { _ in true },
        isCurrent: @MainActor () -> Bool, confirm: @MainActor () async -> Bool,
        write: @MainActor (Item) async throws -> Void
    ) async -> String? {
        guard !removals.hasPending, !isLoading, !isLoadingMore else { return nil }
        let snapshot = items
        let targets = snapshot.filter { ids.contains($0.id) && canRemove($0) }
        guard !targets.isEmpty else { return nil }
        let removals = removals
        discardStagedPage()
        isRemovingBatch = true
        let targetIDs = targets.map(\.id)
        for id in targetIDs {
            _ = removals.begin(id)
            removals.hide(id)
        }
        items.removeAll { removals.hiddenIDs.contains($0.id) }
        contentRevision += 1
        let byID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0) })
        let result = await LibraryBatchRemoval.perform(ids: targetIDs,
            isCurrent: { self.removals === removals && isCurrent() }, confirm: confirm,
            remove: { id in
                if let item = byID[id] { try await write(item) }
            })
        guard self.removals === removals, isCurrent() else { return nil }
        items = snapshot.filter { !result.succeeded.contains($0.id) }
        finishRemoval(of: result.succeeded)
        for id in targetIDs { removals.finish(id) }
        isRemovingBatch = false
        return result.error
    }

    private func finishRemoval(of ids: Set<Item.ID>) {
        contentRevision += 1
        selectedIDs.subtract(ids)
        if selectedIDs.isEmpty { isSelecting = false }
    }
}
