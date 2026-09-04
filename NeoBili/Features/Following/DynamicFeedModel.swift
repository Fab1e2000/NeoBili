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

    private(set) var entries: [DynamicEntry] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?

    /// 下一页的游标。空串表示要从头取。
    private var offset = ""
    private var page = 1
    private var hasMore = true
    private var reloadTask: Task<Void, Never>?

    /// 本地叠加的点赞状态：动态 id -> 是否已赞。
    /// 点一下就把整页重拉一遍太贵，所以这里只记差量，展示时和接口回报的状态叠加。
    private(set) var likeOverrides: [String: Bool] = [:]
    /// 正在请求中的动态，用来防连点。
    private var likingIDs: Set<String> = []

    init(source: Source) {
        self.source = source
    }

    // MARK: - 加载

    func loadInitial() async {
        guard entries.isEmpty else { return }
        await reload()
    }

    func refresh() async {
        await reload()
    }

    private func reload() async {
        reloadTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performReload()
        }
        reloadTask = task
        await task.value
    }

    private func performReload() async {
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            isLoadingMore = false
        }

        do {
            let feed = try await fetch(page: 1, offset: nil)
            guard !Task.isCancelled else { return }
            entries = Self.removingDuplicates(feed.entries)
            offset = feed.offset
            hasMore = feed.hasMore && !feed.offset.isEmpty
            page = 1
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            entries = []
            hasMore = false
            errorMessage = error.localizedDescription
        }
    }

    /// 滚到列表尾部附近时取下一页。失败就静默收手，再滚一次会自动重试。
    func loadMoreIfNeeded(current entry: DynamicEntry) async {
        guard hasMore, !isLoading, !isLoadingMore,
              let index = entries.firstIndex(of: entry),
              index >= entries.count - 4
        else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let feed = try await fetch(page: page + 1, offset: offset)
            guard !Task.isCancelled else { return }
            page += 1
            offset = feed.offset
            hasMore = feed.hasMore && !feed.offset.isEmpty && !feed.items.isEmpty
            let existing = Set(entries.map(\.id))
            entries.append(contentsOf: Self.removingDuplicates(feed.entries).filter { !existing.contains($0.id) })
        } catch {
            // 翻页失败不打扰用户：列表里已有的内容仍然能看。
        }
    }

    private func fetch(page: Int, offset: String?) async throws -> DynamicFeedPage {
        switch source {
        case .following:
            try await BiliAPI.followedDynamics(page: page, offset: offset)
        case .space(let hostMid):
            try await BiliAPI.spaceDynamics(hostMid: hostMid, offset: offset)
        }
    }

    /// 合集更新会让同一个稿件在一页里出现两次，重复的 id 会打乱 SwiftUI 的列表标识。
    private static func removingDuplicates(_ entries: [DynamicEntry]) -> [DynamicEntry] {
        var seen = Set<String>()
        return entries.filter { seen.insert($0.id).inserted }
    }

    // MARK: - 点赞

    func isLiked(_ entry: DynamicEntry) -> Bool {
        likeOverrides[entry.id] ?? entry.isLikedByServer
    }

    /// 展示用的点赞数：接口给的原始值，加上本地这一次的增减。
    func likeCount(_ entry: DynamicEntry) -> Int {
        guard let overridden = likeOverrides[entry.id], overridden != entry.isLikedByServer else {
            return entry.likeCount
        }
        return max(0, entry.likeCount + (overridden ? 1 : -1))
    }

    /// 点赞 / 取消点赞。界面先变，失败再改回去并把接口原话交给调用方提示。
    func toggleLike(_ entry: DynamicEntry, isLoggedIn: Bool) async -> String? {
        guard isLoggedIn else { return "请先登录" }
        guard !likingIDs.contains(entry.id) else { return nil }
        likingIDs.insert(entry.id)
        defer { likingIDs.remove(entry.id) }

        let wasLiked = isLiked(entry)
        likeOverrides[entry.id] = !wasLiked

        do {
            try await BiliAPI.likeDynamic(id: entry.id, like: !wasLiked)
            return nil
        } catch {
            likeOverrides[entry.id] = wasLiked
            return error.isCancellation ? nil : error.localizedDescription
        }
    }
}
