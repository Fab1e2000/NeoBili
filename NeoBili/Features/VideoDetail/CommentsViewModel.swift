import Foundation

@MainActor
@Observable
final class CommentsViewModel {
    /// 评论区的定位。视频是 av 号 + `type: 1`，动态是 `comment_id_str` +
    /// 它自己的评论区类型（图文 11、纯文字 17），所以这里存的不是 bvid。
    let oid: Int
    let type: Int

    private(set) var comments: [Comment] = []
    /// 一级评论总条数，底部标签栏上显示的就是它。
    private(set) var totalCount = 0
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?
    private(set) var hasMore = true

    private(set) var submittedReplies: [Int: [Comment]] = [:]
    @ObservationIgnored private var drafts: [Int: CommentDraft] = [:]

    func commentDraft(root: Int) -> CommentDraft {
        if let draft = drafts[root] { return draft }
        let draft = CommentDraft()
        drafts[root] = draft
        return draft
    }

    func clearCommentDrafts() {
        for draft in drafts.values {
            draft.text = ""
            draft.target = nil
        }
    }

    private var nextPage = 1
    private let fetchComments: @MainActor (Int, Int, Int) async throws -> CommentPage

    /// 只显示服务器确认返回的新评论，不构造虚假的本地发送成功记录。
    func acceptSubmission(_ comment: Comment?, root: Int?) {
        guard let comment else { return }
        if let root {
            if submittedReplies[root]?.contains(where: { $0.rpid == comment.rpid }) != true {
                submittedReplies[root, default: []].insert(comment, at: 0)
            }
            var replies = loadedReplies[root] ?? comments.first(where: { $0.rpid == root })?.replies ?? []
            if !replies.contains(where: { $0.rpid == comment.rpid }) { replies.insert(comment, at: 0) }
            loadedReplies[root] = replies
        } else if !comments.contains(where: { $0.rpid == comment.rpid }) {
            comments.insert(comment, at: 0)
            totalCount += 1
        }
    }

    // MARK: - 评论点赞

    /// 本地叠加的点赞状态：rpid -> 是否已赞。
    ///
    /// 点完一条评论不值得把整页评论重新拉一遍，而 `Comment` 又是不可变的值类型
    /// （还嵌套在楼中楼里），所以这里只记差量，展示时和接口回报的状态叠加。
    private(set) var likeOverrides: [Int: Bool] = [:]
    /// 正在请求中的评论，用来防连点。
    private var likingRpids: Set<Int> = []
    /// 点赞失败时的提示，由评论页弹出。
    var actionMessage: String?

    func isLiked(_ comment: Comment) -> Bool {
        likeOverrides[comment.rpid] ?? comment.isLikedByServer
    }

    /// 展示用的点赞数：接口给的原始值，加上本地这一次的增减。
    func likeCount(_ comment: Comment) -> Int {
        guard let overridden = likeOverrides[comment.rpid], overridden != comment.isLikedByServer else {
            return comment.like
        }
        return max(0, comment.like + (overridden ? 1 : -1))
    }

    func toggleLike(_ comment: Comment, isLoggedIn: Bool) async {
        guard isLoggedIn else {
            actionMessage = "请先登录"
            return
        }
        guard !likingRpids.contains(comment.rpid) else { return }
        likingRpids.insert(comment.rpid)
        defer { likingRpids.remove(comment.rpid) }

        let wasLiked = isLiked(comment)
        likeOverrides[comment.rpid] = !wasLiked

        do {
            try await BiliAPI.likeComment(oid: oid, type: type, rpid: comment.rpid, like: !wasLiked)
        } catch {
            likeOverrides[comment.rpid] = wasLiked
            actionMessage = error.localizedDescription
        }
    }

    init(oid: Int, type: Int,
         fetchComments: @escaping @MainActor (Int, Int, Int) async throws -> CommentPage = {
             try await BiliAPI.comments(oid: $0, type: $1, page: $2)
         }) {
        self.oid = oid
        self.type = type
        self.fetchComments = fetchComments
    }

    /// 视频评论区的便利入口：`type` 固定是 1。
    convenience init(aid: Int) {
        self.init(oid: aid, type: 1)
    }

    /// 第一次切到评论页时调用。已经加载过就直接返回，
    /// 所以在简介和评论之间来回切换不会重复请求。
    func loadInitial() async {
        guard comments.isEmpty, !isLoading, errorMessage == nil else { return }
        isLoading = true
        await loadNextPage()
        isLoading = false
    }

    /// 快滚到列表末尾时翻下一页。
    func loadMoreIfNeeded(current comment: Comment) async {
        guard hasMore, !isLoading, !isLoadingMore, errorMessage == nil else { return }
        // 只有接近末尾的那几条才触发翻页，中间的评论滚过时不会重复请求。
        guard comments.suffix(5).contains(where: { $0.id == comment.id }) else { return }
        isLoadingMore = true
        await loadNextPage()
        isLoadingMore = false
    }

    // MARK: - 楼中楼

    /// 已经点开楼中楼的那些评论。
    private(set) var expandedCommentIDs: Set<Int> = []
    /// 评论 rpid -> 已经完整取回的回复。没有取过的用接口自带的预览。
    private(set) var loadedReplies: [Int: [Comment]] = [:]
    private(set) var loadingReplyIDs: Set<Int> = []
    private(set) var moreRepliesIDs: Set<Int> = []
    private var replyNextPage: [Int: Int] = [:]
    private(set) var replyErrors: [Int: String] = [:]

    func isExpanded(_ comment: Comment) -> Bool {
        expandedCommentIDs.contains(comment.id)
    }

    func isLoadingReplies(_ comment: Comment) -> Bool {
        loadingReplyIDs.contains(comment.id)
    }

    func hasMoreReplies(_ comment: Comment) -> Bool {
        moreRepliesIDs.contains(comment.id)
    }

    /// 展开时用完整列表，收起时用接口跟着一级评论一起返回的那几条预览。
    func replies(for comment: Comment) -> [Comment] {
        if isExpanded(comment), let loaded = loadedReplies[comment.id] {
            return loaded
        }
        var known: Set<Int> = []
        return ((submittedReplies[comment.id] ?? []) + (comment.replies ?? []))
            .filter { known.insert($0.rpid).inserted }
    }

    /// 仅供间距测试：跳过网络直接把楼中楼置为展开状态。
    func setExpandedForTesting(rootId: Int, replies: [Comment]) {
        expandedCommentIDs.insert(rootId)
        loadedReplies[rootId] = replies
    }

    func shouldShowAllReplies(_ comment: Comment) -> Bool {
        replyErrors[comment.id] != nil || (!isExpanded(comment) && comment.rcount > replies(for: comment).count)
    }

    /// 就地展开楼中楼。
    ///
    /// 界面上已经没有入口了——「查看全部回复」和点击楼中楼区块现在都走单独页面。
    /// 保留它是因为 `DynamicFeatureTests` 还在覆盖"重复展开不会收起"这条行为。
    func expandReplies(for comment: Comment) async {
        expandedCommentIDs.insert(comment.id)
        guard comment.rcount > (comment.replies ?? []).count || replyErrors[comment.id] != nil else { return }
        guard loadedReplies[comment.id] == nil || replyErrors[comment.id] != nil else { return }
        await loadMoreReplies(for: comment)
    }

    /// 单独页面用的完整回复列表。
    ///
    /// 和 `replies(for:)` 不同，它不看展开状态：卡片上那一小块预览仍然只显示
    /// 接口跟着一级评论一起返回的那几条，不会因为进过一次单独页面就变长。
    func allReplies(for comment: Comment) -> [Comment] {
        loadedReplies[comment.id] ?? comment.replies ?? []
    }

    /// 单独页面第一次打开时把第一页回复取回来。已经取过就直接返回。
    func loadRepliesIfNeeded(for comment: Comment) async {
        guard replyNextPage[comment.id] == nil else { return }
        await loadMoreReplies(for: comment)
    }

    func loadMoreReplies(for comment: Comment) async {
        let rootId = comment.id
        guard !loadingReplyIDs.contains(rootId) else { return }
        replyErrors[rootId] = nil
        loadingReplyIDs.insert(rootId)
        defer { loadingReplyIDs.remove(rootId) }

        let page = replyNextPage[rootId] ?? 1
        do {
            let result = try await BiliAPI.commentReplies(oid: oid, type: type, rootId: rootId, page: page)
            let incoming = result.replies ?? []
            var all = loadedReplies[rootId] ?? []
            let existingIDs = Set(all.map(\.id))
            all.append(contentsOf: incoming.filter { !existingIDs.contains($0.id) })
            loadedReplies[rootId] = all
            replyNextPage[rootId] = page + 1

            if incoming.isEmpty || all.count >= result.page.count {
                moreRepliesIDs.remove(rootId)
            } else {
                moreRepliesIDs.insert(rootId)
            }
        } catch {
            // 保留已显示的预览/回复和页码，允许重试这一页。
            moreRepliesIDs.remove(rootId)
            replyErrors[rootId] = error.localizedDescription
        }
    }

    func retry() async {
        guard !isLoading, !isLoadingMore else { return }
        errorMessage = nil
        if comments.isEmpty {
            await loadInitial()
        } else {
            isLoadingMore = true
            defer { isLoadingMore = false }
            await loadNextPage()
        }
    }

    private func loadNextPage() async {
        do {
            let page = try await fetchComments(oid, type, nextPage)
            try Task.checkCancellation()
            totalCount = page.page.count
            let newComments = page.replies ?? []
            guard !newComments.isEmpty else {
                // 接口在没有更多内容时返回空数组，用它作为结束条件。
                hasMore = false
                return
            }
            // 热门排序下相邻两页偶尔会返回同一条评论，重复的会让 ForEach 的 id 冲突。
            var existingIDs = Set(comments.map(\.id))
            comments.append(contentsOf: newComments.filter { existingIDs.insert($0.id).inserted })
            nextPage += 1
            if comments.count >= totalCount {
                hasMore = false
            }
        } catch {
            guard !error.isCancellation else { return }
            errorMessage = error.localizedDescription
        }
    }
}
