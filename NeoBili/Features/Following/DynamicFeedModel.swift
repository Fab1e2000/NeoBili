import Foundation

/// 动态列表的公共部分。
///
/// 关注页和 UP 主空间页的动态只有「问哪个接口要下一页」不同，其余——游标
/// 翻页、去重、点赞的即时状态——完全一样，所以放在同一个模型里，两边各持有
/// 一个实例。
@MainActor
@Observable
final class DynamicFeedModel {
    enum Source: Equatable {
        /// 关注的所有 UP 主。
        case following
        /// 某一个 UP 主自己的动态。
        case space(hostMid: Int)
    }

    let source: Source
    private let likeStore: VideoLikeStore
    private let accountSessionID: UUID

    private(set) var entriesGeneration = 0
    private(set) var entries: [DynamicEntry] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?

    /// 下一页的游标。空串表示要从头取。
    private var offset = ""
    private var page = 1
    private var hasMore = true
    private var pendingRefresh: DynamicFeedPage?
    private var pendingRefreshID: UUID?
    private var reloadTask: Task<Void, Never>?
    private var loadGeneration = UUID()
    private let fetchFeed: @MainActor (Source, Int, String?) async throws -> DynamicFeedPage

    /// 本地叠加的点赞状态：动态 id -> 是否已赞。
    /// 点一下就把整页重拉一遍太贵，所以这里只记差量，展示时和接口回报的状态叠加。
    private(set) var likeOverrides: [String: Bool] = [:]
    /// 正在请求中的动态，用来防连点。
    private var likingIDs: Set<String> = []

    init(source: Source, likeStore: VideoLikeStore = .shared,
         fetchFeed: @escaping @MainActor (Source, Int, String?) async throws -> DynamicFeedPage = { source, page, offset in
             switch source {
             case .following: try await BiliAPI.followedDynamics(page: page, offset: offset)
             case .space(let mid): try await BiliAPI.spaceDynamics(hostMid: mid, offset: offset)
             }
         }) {
        self.source = source
        self.likeStore = likeStore
        self.accountSessionID = likeStore.sessionID
        self.fetchFeed = fetchFeed
    }

    // MARK: - 加载

    func loadInitial() async {
        guard entries.isEmpty, !isLoading else { return }
        await reload()
    }

    func refresh(staged: Bool = false, stagingID: UUID? = nil) async {
        await reload(staged: staged, stagingID: stagingID)
    }

    private func reload(staged: Bool = false, stagingID: UUID? = nil) async {
        guard likeStore.sessionID == accountSessionID else { return }
        pendingRefresh = nil
        reloadTask?.cancel()
        let generation = UUID()
        loadGeneration = generation
        isLoading = true
        isLoadingMore = false
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performReload(generation: generation, staged: staged, stagingID: stagingID)
        }
        reloadTask = task
        await task.value
        if loadGeneration == generation { reloadTask = nil }
    }

    private func performReload(generation: UUID, staged: Bool, stagingID: UUID?) async {
        guard likeStore.sessionID == accountSessionID, loadGeneration == generation, !Task.isCancelled else { return }
        isLoading = true
        errorMessage = nil
        defer {
            if loadGeneration == generation {
                isLoading = false
                isLoadingMore = false
            }
        }

        do {
            let feed = try await fetch(page: 1, offset: nil)
            guard likeStore.sessionID == accountSessionID, loadGeneration == generation, !Task.isCancelled else { return }
            if staged { pendingRefresh = feed; pendingRefreshID = stagingID }
            else { applyRefresh(feed) }
        } catch {
            guard likeStore.sessionID == accountSessionID, loadGeneration == generation, !error.isCancellation else { return }
            errorMessage = error.localizedDescription
        }
    }

    func commitStagedRefresh(id: UUID? = nil) {
        guard id == nil || id == pendingRefreshID else { return }
        guard let feed = pendingRefresh else { return }
        pendingRefresh = nil
        guard likeStore.sessionID == accountSessionID else { return }
        applyRefresh(feed)
    }

    private func applyRefresh(_ feed: DynamicFeedPage) {
        entriesGeneration += 1
        entries = Self.removingDuplicates(feed.entries)
        FollowingReadStore.shared.observe(entries)
        offset = feed.offset
        hasMore = feed.hasMore && !feed.offset.isEmpty
        page = 1
    }

    /// 滚到列表尾部附近时取下一页。失败就静默收手，再滚一次会自动重试。
    func loadMoreIfNeeded(current entry: DynamicEntry) async {
        guard likeStore.sessionID == accountSessionID, hasMore, !isLoading, !isLoadingMore, pendingRefresh == nil,
              let index = entries.firstIndex(of: entry),
              index >= entries.count - 4
        else { return }

        await loadReplacementPage()
    }

    func loadReplacementPage() async {
        guard likeStore.sessionID == accountSessionID, hasMore, !isLoading, !isLoadingMore,
              pendingRefresh == nil else { return }
        let generation = loadGeneration
        isLoadingMore = true
        defer { if loadGeneration == generation { isLoadingMore = false } }

        do {
            let feed = try await fetch(page: page + 1, offset: offset)
            guard likeStore.sessionID == accountSessionID, loadGeneration == generation, !Task.isCancelled else { return }
            page += 1
            offset = feed.offset
            hasMore = feed.hasMore && !feed.offset.isEmpty && !feed.items.isEmpty
            FollowingReadStore.shared.observe(feed.entries)
            let existing = Set(entries.map(\.id))
            entries.append(contentsOf: Self.removingDuplicates(feed.entries).filter { !existing.contains($0.id) })
        } catch {
            // 翻页失败不打扰用户：列表里已有的内容仍然能看。
        }
    }

    private func fetch(page: Int, offset: String?) async throws -> DynamicFeedPage {
        try await fetchFeed(source, page, offset)
    }

    /// 合集更新会让同一个稿件在一页里出现两次，重复的 id 会打乱 SwiftUI 的列表标识。
    private static func removingDuplicates(_ entries: [DynamicEntry]) -> [DynamicEntry] {
        var seen = Set<String>()
        return entries.filter { seen.insert($0.id).inserted }
    }

    // MARK: - 点赞

    func isLiked(_ entry: DynamicEntry) -> Bool {
        // 视频动态的点赞就是稿件点赞，走全 App 共享的差量，
        // 这样视频详情页点完赞回到列表（或反过来）状态一致。
        if let aid = entry.video?.aid {
            return likeStore.isLiked(aid: aid, serverValue: entry.isLikedByServer)
        }
        return likeOverrides[entry.id] ?? entry.isLikedByServer
    }

    /// 展示用的点赞数：接口给的原始值，加上本地这一次的增减。
    func likeCount(_ entry: DynamicEntry) -> Int {
        guard isLiked(entry) != entry.isLikedByServer else {
            return entry.likeCount
        }
        return max(0, entry.likeCount + (isLiked(entry) ? 1 : -1))
    }

    /// 点赞 / 取消点赞。界面先变，失败再改回去并把接口原话交给调用方提示。
    ///
    /// 视频动态点的是稿件本身（`archive/like`），和视频详情页同一个对象；
    /// 文字/图文动态点的是动态（`dyn/thumb`）。
    func toggleLike(_ entry: DynamicEntry, isLoggedIn: Bool) async -> String? {
        guard isLoggedIn, likeStore.sessionID == accountSessionID else { return "请先登录" }
        guard !likingIDs.contains(entry.id) else { return nil }
        likingIDs.insert(entry.id)
        defer { likingIDs.remove(entry.id) }

        let sessionID = likeStore.sessionID
        let wasLiked = isLiked(entry)
        let willBeLiked = !wasLiked
        if let aid = entry.video?.aid {
            likeStore.setOverride(aid: aid, liked: willBeLiked, sessionID: sessionID)
        } else {
            likeOverrides[entry.id] = willBeLiked
        }

        do {
            if let aid = entry.video?.aid {
                try await BiliAPI.likeVideo(aid: aid, like: willBeLiked)
            } else {
                try await BiliAPI.likeDynamic(id: entry.id, like: willBeLiked)
            }
            return nil
        } catch {
            guard likeStore.sessionID == sessionID else { return nil }
            if let aid = entry.video?.aid {
                likeStore.setOverride(aid: aid, liked: wasLiked, sessionID: sessionID)
            } else {
                likeOverrides[entry.id] = wasLiked
            }
            return error.isCancellation ? nil : error.localizedDescription
        }
    }
}
