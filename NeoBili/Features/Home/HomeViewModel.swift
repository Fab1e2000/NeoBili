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

    /// Preserve row/marker ordering while giving each card its own native cell.
    static func collectionItems(_ rows: [HomeFeedRow]) -> [HomeFeedItem] {
        rows.flatMap { row -> [HomeFeedItem] in
            switch row {
            case .videos(let videos): videos.map(HomeFeedItem.video)
            case .lastSeen: [.lastSeen]
            }
        }
    }

    static func group(_ items: [HomeFeedItem]) -> [HomeFeedRow] {
        var rows: [HomeFeedRow] = []
        var pending: [VideoSummary] = []
        var markerAfterPendingRow = false
        for item in items {
            switch item {
            case .video(let video):
                pending.append(video)
                if pending.count == 2 {
                    rows.append(.videos(pending))
                    pending = []
                    if markerAfterPendingRow {
                        rows.append(.lastSeen)
                        markerAfterPendingRow = false
                    }
                }
            case .lastSeen:
                if pending.isEmpty {
                    rows.append(.lastSeen)
                } else {
                    // A refresh/filter may leave an odd number of new cards.
                    // Finish this row in the original video order before placing
                    // the full-width marker; never create a hole just for it.
                    markerAfterPendingRow = true
                }
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
    private(set) var replacementAnimationIDs: Set<String> = []
    private let reportUninterested: (VideoSummary) async throws -> Void

    func markUninterested(_ video: VideoSummary) async -> String? {
        guard !reportingIDs.contains(video.bvid), !uninterestedIDs.contains(video.bvid) else { return nil }
        reportingIDs.insert(video.bvid)
        defer { reportingIDs.remove(video.bvid) }
        do {
            try await reportUninterested(video)
            uninterestedIDs.insert(video.bvid)
            return await replaceUninterested(video)
        } catch { return error.localizedDescription }
    }

    func replaceUninterested(_ video: VideoSummary) async -> String? {
        guard uninterestedIDs.contains(video.bvid), !replacingIDs.contains(video.bvid) else { return nil }
        replacingIDs.insert(video.bvid)
        defer { replacingIDs.remove(video.bvid) }
        do {
            let batch = try await fetchNextBatch()
            let existing = Set(videos.map(\.bvid)).union(uninterestedIDs)
            guard let replacement = batch.first(where: { !existing.contains($0.bvid) }) else {
                return String(localized: "暂时没有新的推荐，请稍后重试")
            }
            // 等待网络期间刷新可能已改变列表，以原视频标识重新定位。
            guard let index = videos.firstIndex(where: { $0.bvid == video.bvid }) else { return nil }
            replacementAnimationIDs.insert(replacement.bvid)
            videos[index] = replacement
            return nil
        } catch { return error.localizedDescription }
    }

    func didShowReplacement(_ id: String) {
        // 每张卡出现都会调用。@Observable 不比较新旧值，集合里没有这个 id 时
        // remove 也算一次修改，会让读过它的每一行跟着重算，所以先判断再删。
        guard replacementAnimationIDs.contains(id) else { return }
        replacementAnimationIDs.remove(id)
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

    /// 按行惰性布局；分隔条放在包含刷新边界的完整一行之后。
    var feedRows: [HomeFeedRow] { HomeFeedRow.group(feedItems) }

    /// 保留原始列表，设置变化时只重算页面内容，关闭过滤后无需重新请求。
    func feedRows(hidingKnownPortraitVideos hidesPortraitVideos: Bool) -> [HomeFeedRow] {
        let visibleItems = feedItems.filter { item in
            guard case .video(let video) = item else { return true }
            return video.canDisplayVideo(hidingPortrait: hidesPortraitVideos)
        }
        return HomeFeedRow.group(visibleItems)
    }

    func hasVisibleVideos(hidingKnownPortraitVideos hidesPortraitVideos: Bool) -> Bool {
        videos.contains { $0.canDisplayVideo(hidingPortrait: hidesPortraitVideos) }
    }

    private var freshIndex = 0
    private let fetchRecommendations: (Int) async throws -> [VideoSummary]
    /// 刷新拿到的新批次先寄存在这里，等界面把旧卡片淡尽再合并进列表。
    /// 数据一到就换列表的话，用户会看到旧卡片在半透明状态下突然变成新卡片。
    private var pendingRefresh: [VideoSummary]?
    private var stageNextRefresh = false
    private var activeLoadTask: Task<Void, Never>?
    private var activeLoadID: UUID?

    private enum LoadReason: Equatable {
        case initial
        case refresh
        case loadMore
    }

    init(defaults _: UserDefaults = .standard,
         reportUninterested: @escaping (VideoSummary) async throws -> Void = BiliAPI.markRecommendationUninterested,
         fetchRecommendations: @escaping (Int) async throws -> [VideoSummary] = BiliAPI.recommendFeed) {
        self.reportUninterested = reportUninterested
        #if PERFORMANCE_DEMO
        if ProcessInfo.processInfo.arguments.contains("--feed-record") || ProcessInfo.processInfo.arguments.contains("--feed-replay") {
            self.fetchRecommendations = { try await PerformanceFeedSource.shared.fetch($0) }
        } else {
            self.fetchRecommendations = fetchRecommendations
        }
        #else
        self.fetchRecommendations = fetchRecommendations
        #endif
    }

    func loadInitial() async {
        guard videos.isEmpty else { return }
        await startLoad(reason: .initial, replacingActiveLoad: false)
    }

    /// `staged` 为真时新批次只寄存不入列，由界面在合适的时机调用
    /// `commitStagedRefresh()` 合并——留给退出动画把旧卡片淡完。
    func refresh(staged: Bool = false) async {
        // 下拉刷新优先级最高：取消可能仍在进行的分页，并立刻开始新的刷新。
        // 刷新从 idx=0 / pull=true 开始；分页游标只在当前推荐会话内递增。
        stageNextRefresh = staged
        await startLoad(reason: .refresh, replacingActiveLoad: true)
    }

    /// 把寄存的新批次合并进列表。没有寄存内容（请求失败、或者没有新推荐）时什么都不做。
    func commitStagedRefresh() {
        guard let batch = pendingRefresh else { return }
        pendingRefresh = nil
        applyRefresh(batch)
    }

    func loadMoreIfNeeded(current video: VideoSummary, hidingKnownPortraitVideos hidesPortraitVideos: Bool = false) async {
        guard !isLoading else { return }
        // 每张卡出现都会调用：只从末尾往前看最后 5 张可见视频，
        // 不在滚动时把整个列表过滤一遍。
        let tail = videos.reversed().lazy
            .filter { $0.canDisplayVideo(hidingPortrait: hidesPortraitVideos) }
            .prefix(5)
        guard tail.contains(where: { $0.bvid == video.bvid }) else { return }
        await startLoad(reason: .loadMore, replacingActiveLoad: false)
    }

    func loadReplacementPage() async {
        await startLoad(reason: .loadMore, replacingActiveLoad: false)
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
            freshIndex = 0
            pendingRefresh = nil
        }

        do {
            let newBatch = try await fetchNextBatch()
            guard activeLoadID == loadID, !Task.isCancelled else { return }
            guard !newBatch.isEmpty else { return }

            switch reason {
            case .refresh:
                if stageNextRefresh {
                    pendingRefresh = newBatch
                } else {
                    applyRefresh(newBatch)
                }
            case .initial, .loadMore:
                appendUnique(newBatch)
            }
        } catch {
            guard activeLoadID == loadID, !Self.isCancellation(error) else { return }
            // 与 PiliPlus 一致：已有推荐时刷新失败也保留旧内容，不把页面替换成错误页。
            errorMessage = error.localizedDescription
        }
    }

    /// 与 PiliPlus 一致，失败保留原列表，不用热门榜替代个性化推荐。
    private func fetchNextBatch() async throws -> [VideoSummary] {
        let requestIndex = freshIndex
        let batch = try await fetchRecommendations(requestIndex)
        try Task.checkCancellation()
        if !batch.isEmpty { freshIndex = requestIndex == Int.max ? 1 : requestIndex + 1 }
        return batch
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

}
