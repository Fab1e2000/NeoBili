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

    private var nextPage = 1

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

    init(oid: Int, type: Int) {
        self.oid = oid
        self.type = type
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
        guard hasMore, !isLoading, !isLoadingMore else { return }
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
        return comment.replies ?? []
    }

    /// 仅供间距测试：跳过网络直接把楼中楼置为展开状态。
    func setExpandedForTesting(rootId: Int, replies: [Comment]) {
        expandedCommentIDs.insert(rootId)
        loadedReplies[rootId] = replies
    }

    /// 点「查看全部回复」/「收起」。第一次展开时才请求，之后再展开直接用缓存。
    func toggleReplies(for comment: Comment) async {
        guard !expandedCommentIDs.contains(comment.id) else {
            expandedCommentIDs.remove(comment.id)
            return
        }
        expandedCommentIDs.insert(comment.id)
        guard loadedReplies[comment.id] == nil else { return }
        await loadMoreReplies(for: comment)
    }

    func loadMoreReplies(for comment: Comment) async {
        let rootId = comment.id
        guard !loadingReplyIDs.contains(rootId) else { return }
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
            // 楼中楼取不到时保留已有内容，不把整条评论变成错误状态。
            moreRepliesIDs.remove(rootId)
            if loadedReplies[rootId] == nil {
                loadedReplies[rootId] = comment.replies ?? []
            }
        }
    }

    func retry() async {
        errorMessage = nil
        hasMore = true
        await loadInitial()
    }

    private func loadNextPage() async {
        do {
            let page = try await BiliAPI.comments(oid: oid, type: type, page: nextPage)
            totalCount = page.page.count
            let newComments = page.replies ?? []
            guard !newComments.isEmpty else {
                // 接口在没有更多内容时返回空数组，用它作为结束条件。
                hasMore = false
                return
            }
            // 热门排序下相邻两页偶尔会返回同一条评论，重复的会让 ForEach 的 id 冲突。
            let existingIDs = Set(comments.map(\.id))
            comments.append(contentsOf: newComments.filter { !existingIDs.contains($0.id) })
            nextPage += 1
            if comments.count >= totalCount {
                hasMore = false
            }
        } catch {
            errorMessage = error.localizedDescription
            hasMore = false
        }
    }
}
