import Foundation

/// 首页网格中可能出现普通视频，也可能出现“上次看到这里”提示卡。
/// 把两种内容放进同一个列表后，SwiftUI 才能稳定地记住每一张卡片的位置。
enum HomeFeedItem: Identifiable {
    case video(VideoSummary)
    case lastSeen

    var id: String {
        switch self {
        case .video(let video): "video-\(video.bvid)"
        case .lastSeen: "last-seen-marker"
        }
    }
}

enum HomeFeedRow: Identifiable {
    case videos([VideoSummary])
    case lastSeen

    var id: String {
        switch self {
        case .videos(let videos): "row-\(videos[0].bvid)"
        case .lastSeen: "last-seen-row"
        }
    }

    static func group(_ items: [HomeFeedItem]) -> [HomeFeedRow] {
        var rows: [HomeFeedRow] = []
        var pending: [VideoSummary] = []
        for item in items {
            switch item {
            case .video(let video):
                pending.append(video)
                if pending.count == 2 { rows.append(.videos(pending)); pending = [] }
            case .lastSeen:
                if !pending.isEmpty { rows.append(.videos(pending)); pending = [] }
                rows.append(.lastSeen)
            }
        }
        if !pending.isEmpty { rows.append(.videos(pending)) }
        return rows
    }
}

@MainActor
@Observable
final class HomeViewModel {
    private(set) var videos: [VideoSummary] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?
    private(set) var lastRefreshAt: Int?
    private(set) var uninterestedIDs: Set<String> = []
    private(set) var reportingIDs: Set<String> = []
    private(set) var replacingIDs: Set<String> = []
    private let reportUninterested: (VideoSummary) async throws -> Void

    func markUninterested(_ video: VideoSummary) async -> String? {
        guard !reportingIDs.contains(video.bvid), !uninterestedIDs.contains(video.bvid) else { return nil }
        reportingIDs.insert(video.bvid)
        defer { reportingIDs.remove(video.bvid) }
        do {
            try await reportUninterested(video)
            uninterestedIDs.insert(video.bvid)
            return nil
        } catch { return error.localizedDescription }
    }

    func replaceUninterested(_ video: VideoSummary) async -> String? {
        guard uninterestedIDs.contains(video.bvid), replacingIDs.isEmpty else { return nil }
        replacingIDs.insert(video.bvid)
        defer { replacingIDs.remove(video.bvid) }
        do {
            let batch = try await fetchNextBatch()
            let existing = Set(videos.map(\.bvid)).union(uninterestedIDs)
            guard let replacement = batch.first(where: { !existing.contains($0.bvid) }) else {
                return "暂时没有新的推荐，请稍后重试"
            }
            // 等待网络期间刷新可能已改变列表，以原视频标识重新定位。
            guard let index = videos.firstIndex(where: { $0.bvid == video.bvid }) else { return nil }
            videos[index] = replacement
            return nil
        } catch { return error.localizedDescription }
    }

    /// 这是页面真正显示的顺序。提示卡会被插在“本次刷新内容”和“上次内容”之间。
    var feedItems: [HomeFeedItem] {
        var items = videos.map(HomeFeedItem.video)
        if let lastRefreshAt,
           lastRefreshAt >= 0,
           lastRefreshAt <= items.count {
            items.insert(.lastSeen, at: lastRefreshAt)
        }
        return items
    }

    /// 按行惰性布局，刷新分界独占两列，不与旧视频混在同一行。
    var feedRows: [HomeFeedRow] { HomeFeedRow.group(feedItems) }

    private static let freshIndexKey = "neobili.recommendFreshIndex"
    private static let popularPageKey = "neobili.popularFallbackPage"

    private let defaults: UserDefaults
    private var freshIndex: Int
    private var popularPage: Int
    private var useFallback = false
    private var activeLoadTask: Task<Void, Never>?
    private var activeLoadID: UUID?

    private enum LoadReason: Equatable {
        case initial
        case refresh
        case loadMore
    }

    init(defaults: UserDefaults = .standard,
         reportUninterested: @escaping (VideoSummary) async throws -> Void = BiliAPI.markRecommendationUninterested) {
        self.defaults = defaults
        self.reportUninterested = reportUninterested
        freshIndex = max(defaults.integer(forKey: Self.freshIndexKey), 1)
        popularPage = max(defaults.integer(forKey: Self.popularPageKey), 1)
    }

    func loadInitial() async {
        guard videos.isEmpty else { return }
        await startLoad(reason: .initial, replacingActiveLoad: false)
    }

    func refresh() async {
        // 下拉刷新优先级最高：取消可能仍在进行的分页，并立刻开始新的刷新。
        // freshIndex 不归零是 NeoBili 对 PiliPlus 逻辑的必要适配，防止重启 App 后再次拿到同一批推荐。
        await startLoad(reason: .refresh, replacingActiveLoad: true)
    }

    func loadMoreIfNeeded(current video: VideoSummary) async {
        guard let index = videos.firstIndex(of: video) else { return }
        if index >= videos.count - 5, !isLoading {
            await startLoad(reason: .loadMore, replacingActiveLoad: false)
        }
    }

    /// 网络任务由 ViewModel 自己持有，不再依附某一张正在滚动的卡片。
    /// 因此 SwiftUI 回收卡片或结束下拉动画时，请求不会被意外取消。
    private func startLoad(reason: LoadReason, replacingActiveLoad: Bool) async {
        if let activeLoadTask {
            guard replacingActiveLoad else {
                await activeLoadTask.value
                return
            }
            activeLoadTask.cancel()
        }

        let loadID = UUID()
        activeLoadID = loadID
        isLoading = true
        isLoadingMore = reason == .loadMore
        errorMessage = nil

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad(reason: reason, loadID: loadID)
        }
        activeLoadTask = task
        await task.value

        if activeLoadID == loadID {
            activeLoadTask = nil
        }
    }

    private func performLoad(reason: LoadReason, loadID: UUID) async {
        defer {
            if activeLoadID == loadID {
                isLoading = false
                isLoadingMore = false
            }
        }

        if reason == .refresh {
            // 每次手动刷新都先尝试个性化推荐，失败后才使用热门榜。
            useFallback = false
        }

        do {
            let newBatch = try await fetchNextBatch()
            guard activeLoadID == loadID, !Task.isCancelled else { return }
            guard !newBatch.isEmpty else { return }

            switch reason {
            case .refresh:
                applyRefresh(newBatch)
            case .initial, .loadMore:
                appendUnique(newBatch)
            }
        } catch {
            guard activeLoadID == loadID, !Self.isCancellation(error) else { return }
            // 与 PiliPlus 一致：已有推荐时刷新失败也保留旧内容，不把页面替换成错误页。
            if videos.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// 先请求推荐；推荐接口不可用时，再退回热门列表。
    private func fetchNextBatch() async throws -> [VideoSummary] {
        if !useFallback {
            do {
                let requestIndex = freshIndex
                advanceFreshIndex()
                let batch = try await BiliAPI.recommendFeed(freshIndex: requestIndex)
                try Task.checkCancellation()
                if !batch.isEmpty {
                    return batch
                }
                useFallback = true
            } catch {
                guard !Self.isCancellation(error) else { throw error }
                useFallback = true
            }
        }

        try Task.checkCancellation()
        return try await loadPopularBatch()
    }

    /// 复刻 PiliPlus 的保留刷新：新内容放在上面，旧内容接在提示卡之后。
    /// 旧列表超过 200 条时只保留前 50 条，避免连续刷新让内存无限增长。
    private func applyRefresh(_ batch: [VideoSummary]) {
        let newVideos = Self.removingDuplicates(from: batch).filter { !uninterestedIDs.contains($0.bvid) }
        guard !newVideos.isEmpty else { return }

        guard !videos.isEmpty else {
            videos = newVideos
            lastRefreshAt = nil
            return
        }

        let keepCount = videos.count > 200 ? 50 : videos.count
        let newIDs = Set(newVideos.map(\.bvid))
        let previousVideos = videos.prefix(keepCount).filter { !newIDs.contains($0.bvid) }

        videos = newVideos + previousVideos
        lastRefreshAt = previousVideos.isEmpty ? nil : newVideos.count
    }

    /// 分页只追加尚未出现的视频，避免重复 bvid 破坏 SwiftUI 卡片标识。
    private func appendUnique(_ batch: [VideoSummary]) {
        let existingIDs = Set(videos.map(\.bvid))
        let uniqueBatch = Self.removingDuplicates(from: batch)
            .filter { !existingIDs.contains($0.bvid) && !uninterestedIDs.contains($0.bvid) }
        videos.append(contentsOf: uniqueBatch)
    }

    private static func removingDuplicates(from videos: [VideoSummary]) -> [VideoSummary] {
        var seen = Set<String>()
        return videos.filter { seen.insert($0.bvid).inserted }
    }

    /// URLSession 有时抛出 `CancellationError`，有时抛出含义相同的
    /// `URLError.cancelled`。这里统一识别，避免向用户显示“Cancelled”。
    private static func isCancellation(_ error: Error) -> Bool {
        Task.isCancelled
            || error is CancellationError
            || (error as? URLError)?.code == .cancelled
    }

    /// 读取热门榜的下一页。如果已经到达最后一页，就记住下次从第 1 页开始。
    /// 若启动 App 时保存的页码早已过期，本次会立即改请求第 1 页。
    private func loadPopularBatch() async throws -> [VideoSummary] {
        let requestPage = popularPage
        advancePopularPage()
        let feedPage = try await BiliAPI.popularVideos(page: requestPage)

        if feedPage.noMore {
            setPopularPage(1)
        }
        guard feedPage.list.isEmpty, requestPage != 1 else {
            return feedPage.list
        }

        let firstPage = try await BiliAPI.popularVideos(page: 1)
        setPopularPage(firstPage.noMore ? 1 : 2)
        return firstPage.list
    }

    /// Persist the next cursor before starting the request. If the process is
    /// terminated immediately after receiving a feed, the next launch still
    /// cannot repeat the same cursor and batch.
    private func advanceFreshIndex() {
        freshIndex = freshIndex == Int.max ? 1 : freshIndex + 1
        defaults.set(freshIndex, forKey: Self.freshIndexKey)
    }

    private func advancePopularPage() {
        setPopularPage(popularPage == Int.max ? 1 : popularPage + 1)
    }

    private func setPopularPage(_ page: Int) {
        popularPage = page
        defaults.set(popularPage, forKey: Self.popularPageKey)
    }
}
