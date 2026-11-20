import Foundation
import Observation
import NeoBiliDomain

@MainActor @Observable
final class FavoriteFolderListModel {
    /// 手动刷新取回但还没换进列表的第一页。
    private struct StagedPage {
        let videos: [FavMedia]
        let hasMore: Bool
        /// 取回时的移除状态；换入前若又发生过移除，这份快照已过期。
        let revision: UUID
    }

    private var stagedPage: StagedPage?
    private(set) var videos: [FavMedia] = []
    private var page = 1
    private(set) var hasMore = true
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?
    /// 正在删除的条目。刷新结果会排除它们，避免把刚移出的视频带回来。
    private(set) var removals = ListRemovalState<Int>()
    private var loadID = UUID()
    private(set) var entranceGeneration = 0
    var isSelecting = false
    var selectedIDs: Set<Int> = []
    private(set) var isRemovingSelected = false
    /// 列表内容每变一次加一，过滤缓存据此重算；body 的无关重算仍复用结果。
    private(set) var contentRevision = 0

    func discardStagedPage() { stagedPage = nil }

    func reset() {
        loadID = UUID()
        videos = []; selectedIDs = []; isSelecting = false
        contentRevision += 1
        isLoading = false; isLoadingMore = false
        isRemovingSelected = false
        removals = ListRemovalState()
        hasMore = true
        errorMessage = nil
        stagedPage = nil
    }

    func removeSelected(services: ApplicationServices, account: AccountStore, feedback: ActionFeedback, folder: FavFolder, refreshing: Bool) async {
        guard !isRemovingSelected, !isLoading, !isLoadingMore, !removals.hasPending, !refreshing else { return }
        let snapshot = videos
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
        videos.removeAll { ids.contains($0.id) }
        contentRevision += 1
        let result = await LibraryBatchRemoval.perform(ids: targets.map(\.id),
            isCurrent: { account.sessionID == owner },
            confirm: { await feedback.confirmRemoval(String(localized: "已移出收藏夹")) },
            remove: { id in
                guard let target = lookup[id] else { return }
                try await services.library.removeFavorite(folderID: folder.id, aid: target.id, expectedSessionID: identitySession)
            })
        guard account.sessionID == owner else { return }
        videos = snapshot.filter { !result.succeeded.contains($0.id) }
        contentRevision += 1
        selectedIDs.subtract(result.succeeded)
        if selectedIDs.isEmpty { isSelecting = false }
        if let error = result.error { feedback.show(error) }
    }

    func loadIfNeeded(services: ApplicationServices, folder: FavFolder) async {
        guard videos.isEmpty, !isLoading else { return }
        await reload(services: services, folder: folder)
    }

    func stageReload(services: ApplicationServices, feedback: ActionFeedback, folder: FavFolder) async -> Bool {
        await loadFirstPage(services: services, folder: folder, staged: true, onFailure: feedback.show)
    }

    func reload(services: ApplicationServices, folder: FavFolder) async {
        await loadFirstPage(services: services, folder: folder, staged: false) { message in
            if self.videos.isEmpty { self.errorMessage = message }
        }
    }

    @discardableResult
    private func loadFirstPage(services: ApplicationServices, folder: FavFolder, staged: Bool,
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
            let payload = try await services.library.favoriteVideos(folderID: folder.id, page: 1)
            guard loadID == requestID, removals.revision == revision, !Task.isCancelled else { return false }
            stagedPage = StagedPage(
                videos: LibraryPageRules.unique((payload.medias ?? []).filter(\.isVideo), excluding: removals.hiddenIDs),
                hasMore: LibraryPageRules.hasMoreFavorites(rawCount: payload.medias?.count ?? 0),
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
        guard let staged = stagedPage else { return }
        stagedPage = nil
        guard staged.revision == removals.revision, !removals.hasPending else { return }
        entranceGeneration += 1
        videos = staged.videos
        contentRevision += 1
        selectedIDs.formIntersection(Set(videos.map(\.id)))
        if selectedIDs.isEmpty { isSelecting = false }
        page = 2
        hasMore = staged.hasMore
        errorMessage = nil
    }

    func loadMoreIfNeeded(services: ApplicationServices, folder: FavFolder, refreshing: Bool) async {
        guard !isSelecting, hasMore, !isLoadingMore, !isLoading, !refreshing, errorMessage == nil else { return }
        await loadNextPage(services: services, folder: folder, refreshing: refreshing)
    }

    func loadNextPage(services: ApplicationServices, folder: FavFolder, refreshing: Bool) async {
        guard !removals.hasPending, !isRemovingSelected, !refreshing else { return }
        guard stagedPage == nil, hasMore, !isLoadingMore, !isLoading else { return }
        let requestID = UUID()
        loadID = requestID
        let revision = removals.revision
        errorMessage = nil
        isLoading = videos.isEmpty
        isLoadingMore = !videos.isEmpty
        defer {
            if loadID == requestID {
                isLoading = false
                isLoadingMore = false
            }
        }
        do {
            let payload = try await services.library.favoriteVideos(folderID: folder.id, page: page)
            guard loadID == requestID, removals.revision == revision, !Task.isCancelled else { return }
            let incoming = (payload.medias ?? []).filter(\.isVideo)
            let existing = Set(videos.map(\.id))
            videos.append(contentsOf: LibraryPageRules.unique(incoming, excluding: existing.union(removals.hiddenIDs)))
            contentRevision += 1
            // 不足一页说明到底了。
            hasMore = LibraryPageRules.hasMoreFavorites(rawCount: payload.medias?.count ?? 0)
            page += 1
            errorMessage = nil
        } catch {
            guard loadID == requestID, removals.revision == revision, !error.isCancellation else { return }
            errorMessage = error.loadFailureDescription
        }
    }

    /// 撤销或请求失败时将移除的视频放回原位。
    func remove(_ media: FavMedia, services: ApplicationServices, account: AccountStore, feedback: ActionFeedback, folder: FavFolder, refreshing: Bool) async {
        guard !isRemovingSelected, !refreshing, videos.contains(where: { $0.id == media.id }), removals.begin(media.id) else { return }
        let sessionID = account.sessionID
        defer { if account.sessionID == sessionID { removals.finish(media.id) } }
        let identitySession = services.session.currentID()
        var removedIndex: Int?
        do {
            removals.hide(media.id)
            removedIndex = removals.remove(media.id, from: &videos)
            contentRevision += 1
            guard await feedback.confirmRemoval(String(localized: "已移出收藏夹")),
                  account.sessionID == sessionID, !Task.isCancelled else { throw CancellationError() }
            try await services.library.removeFavorite(folderID: folder.id, aid: media.id, expectedSessionID: identitySession)
            guard account.sessionID == sessionID else { return }
            // 同时完成的刷新也不能留下同 ID 的旧条目。
            videos.removeAll { $0.id == media.id }
            contentRevision += 1
            selectedIDs.remove(media.id)
            if selectedIDs.isEmpty { isSelecting = false }
        } catch {
            if account.sessionID == sessionID, let removedIndex {
                removals.restore(media, at: removedIndex, in: &videos)
                contentRevision += 1
            }
            if account.sessionID == sessionID, !error.isCancellation { feedback.show(error.localizedDescription) }
        }
    }
}
