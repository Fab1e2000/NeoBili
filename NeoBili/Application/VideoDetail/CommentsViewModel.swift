#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation

@MainActor @Observable
final class CommentsViewModel {
    @ObservationIgnored private let services: ApplicationServices
    let oid: Int
    let type: Int
    private(set) var uploaderID: Int?
    private(set) var comments: [Comment] = []
    private(set) var pinnedIDs: Set<Int> = []
    private(set) var totalCount = 0
    private var allCount: Int?
    var displayCount: Int { allCount ?? totalCount }
    private(set) var sort: CommentSort = .hot
    private(set) var pendingSort: CommentSort?
    private(set) var isLoading = false
    private(set) var isRefreshing = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?
    var didFailReload: Bool { failedReloadSort != nil }
    private(set) var hasMore = true
    /// Only a successful sort change moves the viewport; refresh preserves it.
    private(set) var scrollRevision = 0
    private(set) var submittedReplies: [Int: [Comment]] = [:]
    private(set) var loadedReplies: [Int: [Comment]] = [:]
    private(set) var loadingReplyIDs: Set<Int> = []
    private(set) var moreRepliesIDs: Set<Int> = []
    private(set) var replyErrors: [Int: String] = [:]
    private(set) var deletingIDs: Set<Int> = []
    private(set) var deletedIDs: Set<Int> = []
    private(set) var likeOverrides: [Int: Bool] = [:]
    var actionMessage: String?

    @ObservationIgnored private var drafts: [Int: CommentDraft] = [:]
    @ObservationIgnored private var commentIDs: Set<Int> = []
    @ObservationIgnored private var replyIDs: [Int: Set<Int>] = [:]
    @ObservationIgnored private var serverCommentIDs: Set<Int> = []
    @ObservationIgnored private var serverReplyIDs: [Int: Set<Int>] = [:]
    @ObservationIgnored private var submittedRoots: [Comment] = []
    @ObservationIgnored private var hasLoadedInitialPage = false
    @ObservationIgnored private var nextPage = 1
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var failedReloadSort: CommentSort?
    @ObservationIgnored private var replyGeneration: [Int: Int] = [:]
    @ObservationIgnored private var replyNextPage: [Int: Int] = [:]
    @ObservationIgnored private var failedReplyRefreshes: Set<Int> = []
    @ObservationIgnored private var likingRpids: Set<Int> = []
    private var serverReplyCounts: [Int: Int] = [:]
    private var replyCountOverrides: [Int: Int] = [:]
    private var latestRoots: [Int: Comment] = [:]
    @ObservationIgnored private var rootCountRevisions: [Int: Int] = [:]

    private struct Mutation {
        let root: Int?
        let revision: Int
        var count = 1
    }
    @ObservationIgnored private var mutationRevision = 0
    @ObservationIgnored private var submissions: [Int: Mutation] = [:]
    @ObservationIgnored private var deletions: [Int: Mutation] = [:]
    @ObservationIgnored private let fetchReplies: @MainActor (Int, Int, Int, Int) async throws -> CommentReplyPage
    @ObservationIgnored private let fetchComments: @MainActor (Int, Int, Int, CommentSort) async throws -> CommentPage

    init(oid: Int, type: Int, uploaderID: Int? = nil, initialCount: Int? = nil, services: ApplicationServices = .live,
         fetchReplies: (@MainActor (Int, Int, Int, Int) async throws -> CommentReplyPage)? = nil,
         fetchComments: (@MainActor (Int, Int, Int, CommentSort) async throws -> CommentPage)? = nil) {
        self.services = services
        self.oid = oid
        self.type = type
        self.allCount = initialCount
        self.uploaderID = uploaderID.flatMap { $0 > 0 ? $0 : nil }
        self.fetchComments = fetchComments ?? { try await services.comment.comments(oid: $0, type: $1, page: $2, sort: $3) }
        self.fetchReplies = fetchReplies ?? { try await services.comment.commentReplies(oid: $0, type: $1, rootId: $2, page: $3) }
    }

    convenience init(aid: Int) { self.init(oid: aid, type: 1) }

    func isUploader(_ comment: Comment) -> Bool { comment.isAuthored(by: uploaderID) }
    func isPinned(_ comment: Comment) -> Bool { pinnedIDs.contains(comment.id) }
    func currentRoot(_ root: Comment) -> Comment { latestRoots[root.id] ?? root }

    func commentDraft(root: Int) -> CommentDraft {
        if let draft = drafts[root] { return draft }
        let draft = CommentDraft()
        drafts[root] = draft
        return draft
    }

    func clearCommentDrafts() {
        for draft in drafts.values { draft.text = ""; draft.target = nil }
    }

    /// Accept only a server-confirmed submission, including one arriving during a reload.
    func acceptSubmission(_ comment: Comment?, root: Int?) {
        guard let comment, !deletedIDs.contains(comment.id), root.map({ !deletedIDs.contains($0) }) ?? true,
              submissions[comment.id] == nil else { return }
        mutationRevision += 1
        submissions[comment.id] = Mutation(root: root, revision: mutationRevision)
        if let count = allCount { allCount = count + 1 }
        if let root {
            submittedReplies[root, default: []].insert(comment, at: 0)
            var replies = loadedReplies[root] ?? latestRoots[root]?.replies ?? []
            if !replies.contains(where: { $0.id == comment.id }) { replies.insert(comment, at: 0) }
            loadedReplies[root] = visibleUnique(replies)
            replyIDs[root] = Set(replies.map(\.id))
            if let count = replyCountOverrides[root] { replyCountOverrides[root] = count + 1 }
        } else if commentIDs.insert(comment.id).inserted {
            submittedRoots.insert(comment, at: 0)
            comments.insert(comment, at: comments.prefix(while: { pinnedIDs.contains($0.id) }).count)
            latestRoots[comment.id] = comment
            totalCount += 1
        }
    }

    func loadInitial() async {
        guard !hasLoadedInitialPage, !isLoading, !isRefreshing, !isLoadingMore, errorMessage == nil else { return }
        await reload(sort: sort)
    }

    func refresh() async { await reload(sort: sort) }

    func changeSort(to newSort: CommentSort) async {
        guard newSort != sort || pendingSort != nil else { return }
        await reload(sort: newSort)
    }

    private func reload(sort requestedSort: CommentSort) async {
        generation += 1
        let request = generation
        let revision = mutationRevision
        let previousSort = sort
        isLoading = comments.isEmpty
        isRefreshing = !comments.isEmpty
        isLoadingMore = false
        pendingSort = requestedSort
        failedReloadSort = nil
        errorMessage = nil
        defer {
            if generation == request { isLoading = false; isRefreshing = false; pendingSort = nil }
        }
        do {
            let page = try await fetchComments(oid, type, 1, requestedSort)
            try Task.checkCancellation()
            guard request == generation else { return }
            sort = requestedSort
            hasLoadedInitialPage = true
            nextPage = 2
            let incoming = page.replies ?? []
            serverCommentIDs = Set(incoming.map(\.id))
            let pinned = visibleUnique(page.pinnedReplies)
            pinnedIDs = Set(pinned.map(\.id))
            // Local submissions remain visible until the server includes them in a page.
            comments = visibleUnique(pinned + submittedRoots + incoming)
            commentIDs = Set(comments.map(\.id))
            absorbRoots(page.pinnedReplies + incoming, revision: revision)
            submittedRoots.removeAll { serverCommentIDs.contains($0.id) || deletedIDs.contains($0.id) }
            if uploaderID == nil { uploaderID = page.uploaderID }
            totalCount = max(comments.count, reconciledCount(page.page.count, root: nil,
                incoming: serverCommentIDs.union(page.pinnedReplies.map(\.id)), since: revision))
            updateAllCount(page, revision: revision)
            hasMore = Self.hasNextPage(incoming: incoming, covered: serverCommentIDs.count,
                                      previousCoverage: 0, page: 1, info: page.page)
            if requestedSort != previousSort { scrollRevision += 1 }
        } catch {
            guard request == generation, !error.isCancellation else { return }
            failedReloadSort = requestedSort
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(current comment: Comment) async {
        guard hasMore, !isLoading, !isRefreshing, !isLoadingMore, errorMessage == nil,
              comments.suffix(5).contains(where: { $0.id == comment.id }) else { return }
        // A tail row leaving the viewport does not cancel a page already in flight.
        let task = Task { await self.loadNextPage() }
        await task.value
    }

    func retry() async {
        guard !isLoading, !isRefreshing, !isLoadingMore else { return }
        if let requested = failedReloadSort { await reload(sort: requested) }
        else if !hasLoadedInitialPage { await reload(sort: sort) }
        else { errorMessage = nil; await loadNextPage() }
    }

    private func loadNextPage() async {
        guard !isLoadingMore, !isLoading, !isRefreshing else { return }
        let request = generation
        let revision = mutationRevision
        let number = nextPage
        let requestedSort = sort
        isLoadingMore = true
        defer { if request == generation { isLoadingMore = false } }
        do {
            let page = try await fetchComments(oid, type, number, requestedSort)
            try Task.checkCancellation()
            guard request == generation else { return }
            let incoming = page.replies ?? []
            let previousCoverage = serverCommentIDs.count
            serverCommentIDs.formUnion(incoming.map(\.id))
            if !page.pinnedReplies.isEmpty {
                pinnedIDs.formUnion(page.pinnedReplies.map(\.id).filter { !deletedIDs.contains($0) })
                let pinned = visibleUnique(page.pinnedReplies + comments.filter { pinnedIDs.contains($0.id) })
                comments = visibleUnique(pinned + comments)
                commentIDs = Set(comments.map(\.id))
            }
            comments.append(contentsOf: incoming.filter { !deletedIDs.contains($0.id) && commentIDs.insert($0.id).inserted })
            absorbRoots(page.pinnedReplies + incoming, revision: revision)
            submittedRoots.removeAll { serverCommentIDs.contains($0.id) }
            nextPage = number + 1
            totalCount = max(comments.count, reconciledCount(page.page.count, root: nil,
                incoming: Set(incoming.map(\.id)), since: revision))
            updateAllCount(page, revision: revision)
            hasMore = Self.hasNextPage(incoming: incoming, covered: serverCommentIDs.count,
                                      previousCoverage: previousCoverage, page: number, info: page.page)
        } catch {
            guard request == generation, !error.isCancellation else { return }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Replies

    func isLoadingReplies(_ comment: Comment) -> Bool { loadingReplyIDs.contains(comment.id) }
    func hasMoreReplies(_ comment: Comment) -> Bool { moreRepliesIDs.contains(comment.id) }

    func replies(for comment: Comment) -> [Comment] {
        guard !deletedIDs.contains(comment.id) else { return [] }
        return visibleUnique((submittedReplies[comment.id] ?? []) + (currentRoot(comment).replies ?? []))
    }

    func shouldShowAllReplies(_ comment: Comment) -> Bool {
        // The name now opens a profile; retain a separate entrance even for a short thread.
        replyErrors[comment.id] != nil || replyCount(for: comment) > 0
    }

    func replyCount(for comment: Comment) -> Int {
        guard !deletedIDs.contains(comment.id) else { return 0 }
        if let count = replyCountOverrides[comment.id] { return max(count, allReplies(for: comment).count) }
        let root = currentRoot(comment)
        let previewIDs = Set((root.replies ?? []).map(\.id))
        let added = (submittedReplies[root.id] ?? []).filter {
            !previewIDs.contains($0.id) && (submissions[$0.id]?.revision ?? 0) > (rootCountRevisions[root.id] ?? 0)
        }.count
        return max(max(root.rcount + added, serverReplyCounts[root.id] ?? 0), allReplies(for: root).count)
    }

    func allReplies(for comment: Comment) -> [Comment] {
        guard !deletedIDs.contains(comment.id) else { return [] }
        if let loaded = loadedReplies[comment.id] { return loaded }
        return visibleUnique(currentRoot(comment).replies ?? [])
    }

    func loadRepliesIfNeeded(for comment: Comment) async {
        guard replyNextPage[comment.id] == nil else { return }
        await loadMoreReplies(for: comment)
    }

    func refreshReplies(for comment: Comment) async {
        guard !deletedIDs.contains(comment.id) else { return }
        replyGeneration[comment.id, default: 0] += 1
        await loadReplyPage(for: comment, replacing: true)
    }

    func retryReplies(for comment: Comment) async {
        if failedReplyRefreshes.contains(comment.id) { await refreshReplies(for: comment) }
        else { await loadMoreReplies(for: comment) }
    }

    func loadMoreReplies(for comment: Comment) async {
        guard !loadingReplyIDs.contains(comment.id), !deletedIDs.contains(comment.id),
              replyNextPage[comment.id] == nil || moreRepliesIDs.contains(comment.id) || replyErrors[comment.id] != nil else { return }
        await loadReplyPage(for: comment, replacing: false)
    }

    private func loadReplyPage(for comment: Comment, replacing: Bool) async {
        let root = comment.id
        let request = replyGeneration[root, default: 0]
        let revision = mutationRevision
        let number = replacing ? 1 : (replyNextPage[root] ?? 1)
        if latestRoots[root] == nil { latestRoots[root] = comment }
        loadingReplyIDs.insert(root)
        replyErrors[root] = nil
        failedReplyRefreshes.remove(root)
        defer { if replyGeneration[root, default: 0] == request { loadingReplyIDs.remove(root) } }
        do {
            let page = try await fetchReplies(oid, type, root, number)
            try Task.checkCancellation()
            guard replyGeneration[root, default: 0] == request, !deletedIDs.contains(root) else { return }
            let incoming = page.replies ?? []
            var known = replacing ? Set<Int>() : (replyIDs[root] ?? [])
            var all = replacing ? (submittedReplies[root] ?? []) : (loadedReplies[root] ?? [])
            known.formUnion(all.map(\.id))
            all.append(contentsOf: incoming.filter { !deletedIDs.contains($0.id) && known.insert($0.id).inserted })
            loadedReplies[root] = visibleUnique(all)
            replyIDs[root] = Set(all.map(\.id))
            replyNextPage[root] = number + 1
            var covered = replacing ? Set<Int>() : (serverReplyIDs[root] ?? [])
            let previousCoverage = covered.count
            covered.formUnion(incoming.map(\.id))
            serverReplyIDs[root] = covered
            let count = reconciledCount(page.page.count, root: root, incoming: Set(incoming.map(\.id)), since: revision)
            serverReplyCounts[root] = count
            if replyCountOverrides[root] != nil { replyCountOverrides[root] = count }
            if Self.hasNextPage(incoming: incoming, covered: covered.count, previousCoverage: previousCoverage,
                                page: number, info: page.page) { moreRepliesIDs.insert(root) }
            else { moreRepliesIDs.remove(root) }
        } catch {
            guard replyGeneration[root, default: 0] == request, !deletedIDs.contains(root), !error.isCancellation else { return }
            replyErrors[root] = error.localizedDescription
            if replacing { failedReplyRefreshes.insert(root) }
            else { moreRepliesIDs.remove(root) }
        }
    }

    func loadMoreRepliesIfNeeded(current reply: Comment, root: Comment) async {
        guard hasMoreReplies(root), !isLoadingReplies(root), replyErrors[root.id] == nil,
              allReplies(for: root).suffix(3).contains(where: { $0.id == reply.id }) else { return }
        let task = Task { await self.loadMoreReplies(for: root) }
        await task.value
    }

    // MARK: Confirmed deletion

    struct Deletion: Identifiable {
        let comment: Comment
        let root: Comment?
        let sessionID: UUID
        var id: Int { comment.id }
    }

    func canDelete(_ comment: Comment, accountID: Int?, isLoggedIn: Bool) -> Bool {
        isLoggedIn && comment.isAuthored(by: accountID) && !deletedIDs.contains(comment.id)
    }

    func deletion(for comment: Comment, root: Comment?, accountID: Int?, isLoggedIn: Bool) -> Deletion? {
        guard canDelete(comment, accountID: accountID, isLoggedIn: isLoggedIn), !deletingIDs.contains(comment.id) else { return nil }
        return Deletion(comment: comment, root: root, sessionID: services.session.currentID())
    }

    func delete(_ deletion: Deletion, accountID: Int?, isLoggedIn: Bool) async {
        let comment = deletion.comment
        guard canDelete(comment, accountID: accountID, isLoggedIn: isLoggedIn),
              deletion.sessionID == services.session.currentID(), deletingIDs.insert(comment.id).inserted else { return }
        defer { deletingIDs.remove(comment.id) }
        do {
            try await services.comment.deleteComment(oid: oid, type: type, rpid: comment.id, expectedSessionID: deletion.sessionID)
            guard deletion.sessionID == services.session.currentID() else { return }
            let root = deletion.root
            let oldReplyCount = root.map { replyCount(for: $0) }
            let removedCount = root == nil ? 1 + replyCount(for: comment) : 1
            mutationRevision += 1
            deletedIDs.insert(comment.id)
            deletions[comment.id] = Mutation(root: root?.id, revision: mutationRevision, count: removedCount)
            if let count = allCount { allCount = max(0, count - removedCount) }
            likeOverrides[comment.id] = nil
            if let root {
                submittedReplies[root.id]?.removeAll { $0.id == comment.id }
                loadedReplies[root.id]?.removeAll { $0.id == comment.id }
                replyIDs[root.id]?.remove(comment.id)
                replyCountOverrides[root.id] = max(0, (oldReplyCount ?? 1) - 1)
            } else {
                comments.removeAll { $0.id == comment.id }
                submittedRoots.removeAll { $0.id == comment.id }
                pinnedIDs.remove(comment.id)
                commentIDs.remove(comment.id)
                totalCount = max(0, totalCount - 1)
                loadedReplies[comment.id] = nil
                submittedReplies[comment.id] = nil
                replyErrors[comment.id] = nil
                moreRepliesIDs.remove(comment.id)
            }
            for draft in drafts.values where draft.target?.parent == comment.id || draft.target?.root == comment.id {
                draft.target = nil // Keep the written text when its reply target disappears.
            }
            actionMessage = String(localized: "评论已删除")
        } catch {
            guard deletion.sessionID == services.session.currentID(), !error.isCancellation else { return }
            actionMessage = String(localized: "删除失败：\(error.localizedDescription)")
        }
    }

    // MARK: Likes

    func isLiked(_ comment: Comment) -> Bool { likeOverrides[comment.id] ?? comment.isLikedByServer }
    func likeCount(_ comment: Comment) -> Int {
        guard let overridden = likeOverrides[comment.id], overridden != comment.isLikedByServer else { return comment.like }
        return max(0, comment.like + (overridden ? 1 : -1))
    }

    func toggleLike(_ comment: Comment, isLoggedIn: Bool) async {
        guard isLoggedIn else { actionMessage = String(localized: "请先登录"); return }
        guard !likingRpids.contains(comment.id), !deletedIDs.contains(comment.id) else { return }
        likingRpids.insert(comment.id)
        defer { likingRpids.remove(comment.id) }
        let wasLiked = isLiked(comment)
        likeOverrides[comment.id] = !wasLiked
        do { try await services.comment.likeComment(oid: oid, type: type, rpid: comment.id, like: !wasLiked) }
        catch {
            guard !deletedIDs.contains(comment.id) else { return }
            likeOverrides[comment.id] = wasLiked
            if !error.isCancellation { actionMessage = error.localizedDescription }
        }
    }

    private func visibleUnique(_ values: [Comment]) -> [Comment] {
        var known: Set<Int> = []
        return values.filter { !deletedIDs.contains($0.id) && known.insert($0.id).inserted }
    }

    private func absorbRoots(_ roots: [Comment], revision: Int) {
        for root in roots where !deletedIDs.contains(root.id) {
            latestRoots[root.id] = root
            rootCountRevisions[root.id] = revision
            if replyCountOverrides[root.id] != nil {
                replyCountOverrides[root.id] = reconciledCount(root.rcount, root: root.id,
                    incoming: Set((root.replies ?? []).map(\.id)), since: revision)
            }
        }
    }

    private func reconciledCount(_ count: Int, root: Int?, incoming: Set<Int>, since revision: Int) -> Int {
        let removed = deletions.filter { $0.value.root == root && ($0.value.revision > revision || incoming.contains($0.key)) }.count
        let added = submissions.filter {
            $0.value.root == root && $0.value.revision > revision && !incoming.contains($0.key) && !deletedIDs.contains($0.key)
        }.count
        return max(0, count - removed + added)
    }

    private func updateAllCount(_ page: CommentPage, revision: Int) {
        guard let count = page.page.allCount else { return }
        let roots = page.pinnedReplies + (page.replies ?? [])
        let incoming = Set(roots.flatMap { [$0.id] + ($0.replies ?? []).map(\.id) })
        let removed = deletions.filter { $0.value.revision > revision || incoming.contains($0.key) }
            .reduce(0) { $0 + $1.value.count }
        let added = submissions.filter {
            $0.value.revision > revision && !incoming.contains($0.key) && !deletedIDs.contains($0.key)
                && !deletedIDs.contains($0.value.root ?? $0.key)
        }.count
        allCount = max(0, count - removed + added)
    }

    /// Pagination uses raw server coverage, never the merged pin/submission count.
    private static func hasNextPage(incoming: [Comment], covered: Int, previousCoverage: Int,
                                    page: Int, info: CommentPageInfo) -> Bool {
        guard !incoming.isEmpty, covered < info.count else { return false }
        guard info.size > 0 else { return covered > previousCoverage }
        let lastPage = info.count / info.size + (info.count % info.size == 0 ? 0 : 1)
        return page < lastPage
    }
}
