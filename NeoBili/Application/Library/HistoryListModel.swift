import Foundation
import Observation
import NeoBiliDomain

@MainActor @Observable
final class HistoryListModel {
    /// 手动刷新取回但还没换进列表的第一页。
    private struct StagedPage {
        let items: [HistoryItem]
        let hasMore: Bool
        let cursorMax: Int
        let cursorViewAt: Int
        /// 取回时的移除状态；换入前若又发生过移除，这份快照已过期。
        let revision: UUID
    }

    private var stagedPage: StagedPage?
    private(set) var items: [HistoryItem] = []
    private var cursorMax = 0
    private var cursorViewAt = 0
    private(set) var hasMore = true
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?
    /// 正在删除的条目。刷新结果会排除它们，避免把刚删掉的记录带回来。
    private(set) var removals = ListRemovalState<String>()
    private var loadID = UUID()
    private(set) var entranceGeneration = 0
    var isSelecting = false
    var selectedIDs: Set<String> = []
    private(set) var isRemovingSelected = false
    /// 列表内容每变一次加一，过滤缓存据此重算；body 的无关重算仍复用结果。
    private(set) var contentRevision = 0

    func discardStagedPage() { stagedPage = nil }

    func reset() {
        loadID = UUID()
        items = []; selectedIDs = []; isSelecting = false
        contentRevision += 1
        isLoading = false; isLoadingMore = false
        isRemovingSelected = false
        removals = ListRemovalState()
        hasMore = true
        errorMessage = nil
        stagedPage = nil
    }

    func removeSelected(services: ApplicationServices, account: AccountStore, feedback: ActionFeedback, refreshing: Bool) async {
        guard !isRemovingSelected, !isLoading, !isLoadingMore, !removals.hasPending, !refreshing else { return }
        let snapshot = items
        let targets = snapshot.filter { selectedIDs.contains($0.id) }
        guard !targets.isEmpty else { return }
        let owner = account.sessionID
        let identitySession = services.session.currentID()
        isRemovingSelected = true
        loadID = UUID()
        for target in targets { _ = removals.begin(target.id); removals.hide(target.id) }
        defer {
            if account.sessionID == owner {
                for target in targets { removals.finish(target.id) }
                isRemovingSelected = false
            }
        }
        let lookup = Dictionary(targets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ids = Set(targets.map(\.id))
        items.removeAll { ids.contains($0.id) }
        contentRevision += 1
        let result = await LibraryBatchRemoval.perform(ids: targets.map(\.id),
            isCurrent: { account.sessionID == owner },
            confirm: { await feedback.confirmRemoval(String(localized: "已移除历史记录")) },
            remove: { id in
                guard let target = lookup[id] else { return }
                try await services.library.deleteHistory(kid: target.kidParam, expectedSessionID: identitySession)
            })
        guard account.sessionID == owner else { return }
        items = snapshot.filter { !result.succeeded.contains($0.id) }
        contentRevision += 1
        selectedIDs.subtract(result.succeeded)
        if selectedIDs.isEmpty { isSelecting = false }
        if let error = result.error { feedback.show(error) }
    }

    func loadIfNeeded(services: ApplicationServices) async {
        guard items.isEmpty, !isLoading else { return }
        await reload(services: services)
    }

    func stageReload(services: ApplicationServices, feedback: ActionFeedback) async -> Bool {
        await loadFirstPage(services: services, staged: true, onFailure: feedback.show)
    }

    func reload(services: ApplicationServices) async {
        await loadFirstPage(services: services, staged: false) { message in
            if self.items.isEmpty { self.errorMessage = message }
        }
    }

    @discardableResult
    private func loadFirstPage(services: ApplicationServices, staged: Bool,
                               onFailure: (String) -> Void) async -> Bool {
        guard !removals.hasPending, !isRemovingSelected else { return false }
        let requestID = UUID()
        loadID = requestID
        let revision = removals.revision
        stagedPage = nil
        isLoadingMore = false
        isLoading = true
        defer { if loadID == requestID { isLoading = false } }
        do {
            let payload = try await services.library.historyPage(max: 0, viewAt: 0)
            guard loadID == requestID, removals.revision == revision, !Task.isCancelled else { return false }
            stagedPage = StagedPage(
                items: LibraryPageRules.unique(payload.allItems.filter(\.isVideo), excluding: removals.hiddenIDs),
                hasMore: LibraryPageRules.advancesHistory(max: payload.cursor?.max,
                    viewAt: payload.cursor?.resolvedViewAt, fromMax: 0, fromViewAt: 0),
                cursorMax: payload.cursor?.max ?? 0,
                cursorViewAt: payload.cursor?.resolvedViewAt ?? 0,
                revision: revision)
            if !staged { commitStagedReload() }
            return true
        } catch {
            guard loadID == requestID, removals.revision == revision, !error.isCancellation else { return false }
            onFailure(error.localizedDescription)
            return false
        }
    }

    func commitStagedReload() {
        guard let page = stagedPage else { return }
        stagedPage = nil
        guard page.revision == removals.revision, !removals.hasPending else { return }
        entranceGeneration += 1
        items = page.items
        contentRevision += 1
        selectedIDs.formIntersection(Set(items.map(\.id)))
        if selectedIDs.isEmpty { isSelecting = false }
        hasMore = page.hasMore
        cursorMax = page.cursorMax
        cursorViewAt = page.cursorViewAt
        errorMessage = nil
    }

    func loadMoreIfNeeded(services: ApplicationServices, refreshing: Bool) async {
        guard !isSelecting, hasMore, !isLoadingMore, !isLoading, !refreshing, errorMessage == nil else { return }
        await loadNextPage(services: services, refreshing: refreshing)
    }

    func loadNextPage(services: ApplicationServices, refreshing: Bool) async {
        guard !removals.hasPending, !isRemovingSelected, !refreshing else { return }
        guard stagedPage == nil, hasMore, !isLoadingMore, !isLoading else { return }
        let requestID = UUID()
        loadID = requestID
        let revision = removals.revision
        errorMessage = nil
        isLoading = items.isEmpty
        isLoadingMore = !items.isEmpty
        defer {
            if loadID == requestID {
                isLoading = false
                isLoadingMore = false
            }
        }
        do {
            let payload = try await services.library.historyPage(max: cursorMax, viewAt: cursorViewAt)
            guard loadID == requestID, removals.revision == revision, !Task.isCancelled else { return }
            let incoming = payload.allItems.filter(\.isVideo)
            let existing = Set(items.map(\.id))
            items.append(contentsOf: LibraryPageRules.unique(incoming, excluding: existing.union(removals.hiddenIDs)))
            contentRevision += 1

            hasMore = LibraryPageRules.advancesHistory(max: payload.cursor?.max,
                viewAt: payload.cursor?.resolvedViewAt, fromMax: cursorMax, fromViewAt: cursorViewAt)
            cursorMax = payload.cursor?.max ?? 0
            cursorViewAt = payload.cursor?.resolvedViewAt ?? 0
            errorMessage = nil
        } catch {
            guard loadID == requestID, removals.revision == revision, !error.isCancellation else { return }
            errorMessage = error.loadFailureDescription
        }
    }

    /// 先移除卡片并提供撤销窗口，确认后提交删除；失败时恢复尚未删除的条目。
    func delete(_ item: HistoryItem, services: ApplicationServices, account: AccountStore, feedback: ActionFeedback, refreshing: Bool) async {
        guard !isRemovingSelected, !refreshing, items.contains(where: { $0.id == item.id }), removals.begin(item.id) else { return }
        let sessionID = account.sessionID
        defer { if account.sessionID == sessionID { removals.finish(item.id) } }
        let identitySession = services.session.currentID()
        var removedIndex: Int?
        do {
            removals.hide(item.id)
            removedIndex = removals.remove(item.id, from: &items)
            contentRevision += 1
            guard await feedback.confirmRemoval(String(localized: "已移除历史记录")),
                  account.sessionID == sessionID, !Task.isCancelled else { throw CancellationError() }
            try await services.library.deleteHistory(kid: item.kidParam, expectedSessionID: identitySession)
            guard account.sessionID == sessionID else { return }
            // 同时完成的刷新也不能留下同 ID 的旧条目。
            items.removeAll { $0.id == item.id }
            contentRevision += 1
            selectedIDs.remove(item.id)
            if selectedIDs.isEmpty { isSelecting = false }
        } catch {
            if account.sessionID == sessionID, let removedIndex {
                removals.restore(item, at: removedIndex, in: &items)
                contentRevision += 1
            }
            if account.sessionID == sessionID, !error.isCancellation { feedback.show(error.localizedDescription) }
        }
    }
}
