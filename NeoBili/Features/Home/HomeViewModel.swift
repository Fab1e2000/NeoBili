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
                if video.isLargeRecommendationCard {
                    if !pending.isEmpty { rows.append(.videos(pending)); pending = [] }
                    if markerAfterPendingRow { rows.append(.lastSeen); markerAfterPendingRow = false }
                    rows.append(.videos([video]))
                    continue
                }
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

enum HomeSheet: Identifiable, Hashable {
    /// 图文卡的动态编号。
    case dynamic(id: String)
    case space(FollowedUp)

    var id: String {
        switch self {
        case .dynamic(let id): "dynamic-\(id)"
        case .space(let up): "space-\(up.mid)"
        }
    }
}

/// 请求推荐时用的是哪个账号、有没有 App 凭据；两者不变，推荐就不必重取。
struct HomeFeedAccount: Equatable, Sendable {
    let accountID: Int?
    let hasAppCredential: Bool

    static func current() async -> HomeFeedAccount {
        let account = await DeviceIdentity.shared.appAccount()
        return HomeFeedAccount(accountID: account.mid, hasAppCredential: account.accessKey != nil)
    }
}

@MainActor
@Observable
final class HomeViewModel {
    private(set) var videos: [VideoSummary] = []
    private(set) var exposurePolicy = RecommendationExposurePolicy()
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?
    private(set) var lastRefreshAt: Int?
    private(set) var reportingIDs: Set<String> = []
    /// 首页从底部弹出的页面：推荐里的图文卡详情，或卡片菜单里的「访问 UP 主页」。
    /// 首页没有导航栈，这两种页面都用弹出页打开。
    var sheet: HomeSheet?
    /// 等用户确认拉黑的 UP 主。
    var pendingBlock: VideoOwner?
    private let defaults: UserDefaults
    private let reportUninterested: (RecommendationFeedbackOptions, RecommendationFeedbackOptions.Reason, UUID) async throws -> Void
    private let cancelUninterested: (RecommendationFeedbackOptions, UUID) async throws -> Void
    private let dislikeVideo: (Int, Bool, UUID) async throws -> Void
    private let blockUser: (Int) async throws -> Void
    private let currentAccount: () async -> HomeFeedAccount
    private let currentSessionID: () -> UUID
    /// 最近一次从第一页取推荐时用的账号。
    private var loadedAccount: HomeFeedAccount?

    /// 登录、退出、换号或刚拿到 App 凭据时重取推荐。启动时恢复账号也会让界面上的账号
    /// 从空变成已登录，但那时第一页本来就是用这个账号取的，不能再刷掉它。
    func refreshIfAccountChanged(to account: HomeFeedAccount) async {
        guard let loadedAccount, loadedAccount != account else { return }
        await refresh()
    }

    /// 与 PiliPlus 一致：选一个原因提交，成功后提示服务端给的文案并移除这张卡。
    func markUninterested(_ video: VideoSummary, reason: RecommendationFeedbackOptions.Reason) async -> String? {
        let session = currentSessionID()
        guard !reportingIDs.contains(video.bvid),
              let options = try? BiliAPI.feedbackOptions(for: video, expectedSessionID: session) else { return nil }
        guard options.dislikeReasons?.contains(reason) == true || options.feedbacks?.contains(reason) == true else { return nil }
        reportingIDs.insert(video.bvid)
        defer { reportingIDs.remove(video.bvid) }
        do {
            try await reportUninterested(options, reason, session)
            guard currentSessionID() == session, !Task.isCancelled else { return nil }
            remove(video)
            return reason.toast ?? String(localized: "已提交")
        } catch {
            guard currentSessionID() == session, !Self.isCancellation(error) else { return nil }
            return error.localizedDescription
        }
    }

    /// 撤销这张卡片的「不感兴趣」，卡片本身不动。
    func cancelUninterested(_ video: VideoSummary) async -> String? {
        let session = currentSessionID()
        guard !reportingIDs.contains(video.bvid),
              let options = try? BiliAPI.feedbackOptions(for: video, expectedSessionID: session) else { return nil }
        reportingIDs.insert(video.bvid)
        defer { reportingIDs.remove(video.bvid) }
        do {
            try await cancelUninterested(options, session)
            guard currentSessionID() == session, !Task.isCancelled else { return nil }
            return String(localized: "成功")
        } catch {
            guard currentSessionID() == session, !Self.isCancellation(error) else { return nil }
            return error.localizedDescription
        }
    }

    /// 网页推荐卡片没有原因可选，和 PiliPlus 一样改用视频点踩：点踩成功后移除卡片，撤销只取消点踩。
    func dislikeWebRecommendation(_ video: VideoSummary, dislike: Bool) async -> String? {
        guard !reportingIDs.contains(video.bvid) else { return nil }
        let session = currentSessionID()
        reportingIDs.insert(video.bvid)
        defer { reportingIDs.remove(video.bvid) }
        do {
            try await dislikeVideo(video.aid, dislike, session)
            guard currentSessionID() == session, !Task.isCancelled else { return nil }
            if dislike { remove(video) }
            return dislike ? String(localized: "点踩成功") : String(localized: "取消踩")
        } catch {
            guard currentSessionID() == session, !Self.isCancellation(error) else { return nil }
            return error.localizedDescription
        }
    }

    /// 拉黑 UP 主：照 PiliPlus 成功后记进本地黑名单，之后的推荐不再出现他。
    /// PiliPlus 只移除当前这张卡；这里把列表里他的卡都移除，免得拉黑后眼前还留着。
    func block(_ owner: VideoOwner) async -> String? {
        let session = currentSessionID()
        do {
            try await blockUser(owner.mid)
            guard currentSessionID() == session, !Task.isCancelled else { return nil }
            RecommendationFilter.block(owner.mid, defaults: defaults)
            // Publish one list mutation, even when the UP owns many cards.
            // Count removals on the fresh side before changing the boundary.
            if let boundary = lastRefreshAt {
                let removed = videos.prefix(boundary).count { $0.owner.mid == owner.mid }
                lastRefreshAt = boundary - removed
            }
            videos.removeAll { $0.owner.mid == owner.mid }
            return String(localized: "已拉黑 \(owner.name)")
        } catch {
            guard currentSessionID() == session, !Self.isCancellation(error) else { return nil }
            return error.localizedDescription
        }
    }

    /// 移除卡片；它在「上次看到这里」之前时，提示卡跟着前移一位。
    private func remove(_ video: VideoSummary) {
        guard let index = videos.firstIndex(where: { $0.bvid == video.bvid }) else { return }
        videos.remove(at: index)
        if let lastRefreshAt, index < lastRefreshAt { self.lastRefreshAt = lastRefreshAt - 1 }
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


    /// 自动刷新明确关闭，服务端返回的间隔不会改变这个策略。
    func claimAutomaticRefresh(_ trigger: AppRecommendationRefreshConfig.Trigger) -> Bool {
        // auto_refresh_state=4: returning to the app or home never consumes another batch.
        false
    }

    private var nextRequest: RecommendationRequest?
    private var appRefreshCursor = 0
    private var cursorSession: UUID?
    private var cursorSource: RecommendationRequest.Source?
    private let fetchRecommendations: (RecommendationRequest) async throws -> RecommendationBatch
    /// 刷新拿到的新批次先寄存在这里，等界面把旧卡片淡尽再合并进列表。
    /// 数据一到就换列表的话，用户会看到旧卡片在半透明状态下突然变成新卡片。
    private var pendingRefresh: (videos: [VideoSummary], refreshCursor: Int?, session: UUID, source: RecommendationRequest.Source)?
    private var stageNextRefresh = false
    private var activeLoadTask: Task<Void, Never>?
    private var activeLoadID: UUID?

    private enum LoadReason: Equatable {
        case initial
        case refresh
        case loadMore
    }

    init(defaults: UserDefaults = .standard,
         reportUninterested: ((RecommendationFeedbackOptions, RecommendationFeedbackOptions.Reason) async throws -> Void)? = nil,
         cancelUninterested: ((RecommendationFeedbackOptions) async throws -> Void)? = nil,
         dislikeVideo: ((Int, Bool) async throws -> Void)? = nil,
         blockUser: @escaping (Int) async throws -> Void = BiliAPI.blockUser,
         currentAccount: @escaping () async -> HomeFeedAccount = HomeFeedAccount.current,
         currentSessionID: @escaping () -> UUID = { DeviceIdentity.shared.loginSessionID },
         feedbackClient: APIClient = .shared,
         fetchRecommendations: @escaping (RecommendationRequest) async throws -> RecommendationBatch = BiliAPI.recommendFeed) {
        self.defaults = defaults
        self.reportUninterested = { options, reason, session in
            if let reportUninterested { try await reportUninterested(options, reason) }
            else {
                try await BiliAPI.feedDislike(options, reason: reason,
                    expectedSessionID: session, client: feedbackClient)
            }
        }
        self.cancelUninterested = { options, session in
            if let cancelUninterested { try await cancelUninterested(options) }
            else {
                try await BiliAPI.feedDislikeCancel(options, expectedSessionID: session, client: feedbackClient)
            }
        }
        self.dislikeVideo = { aid, dislike, session in
            if let dislikeVideo { try await dislikeVideo(aid, dislike) }
            else {
                try await BiliAPI.dislikeVideo(aid: aid, dislike: dislike,
                    expectedSessionID: session, client: feedbackClient)
            }
        }
        self.blockUser = blockUser
        self.currentAccount = currentAccount
        self.currentSessionID = currentSessionID
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
    /// `userInitiated` 为真（下拉、点标签刷新）时照 PiliPlus：正在加载就忽略这次刷新，
    /// 不取消已发出的请求，免得多用掉一页推荐。换账号、换推荐来源的刷新不能被忽略，
    /// 会取消进行中的加载并立刻开始。
    func refresh(staged: Bool = false, userInitiated: Bool = false) async {
        if userInitiated, isLoading { return }
        // App 刷新取当前已采纳批次的首游标；网页刷新仍从第一页开始。
        stageNextRefresh = staged
        await startLoad(reason: .refresh, replacingActiveLoad: true)
    }

    /// 把寄存的新批次合并进列表。没有寄存内容（请求失败、或者没有新推荐）时什么都不做。
    func commitStagedRefresh() {
        guard let batch = pendingRefresh else { return }
        pendingRefresh = nil
        let usesApp = defaults.object(forKey: RecommendationFilter.appRecommendKey) as? Bool ?? true
        guard batch.session == currentSessionID(), batch.source == (usesApp ? .app : .web) else { return }
        applyRefresh(batch.videos)
        appRefreshCursor = batch.refreshCursor ?? 0
    }

    func loadMoreIfNeeded(current video: VideoSummary, hidingKnownPortraitVideos hidesPortraitVideos: Bool = false) async {
        guard !isLoading, pendingRefresh == nil else { return }
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
        // 淡出动画结束前，旧卡片仍可能触发分页回调。新批次尚未提交时
        // 不能把它的下一页追加到旧列表，否则刷新边界与游标都会错位。
        if reason == .loadMore, pendingRefresh != nil { return }
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
        guard activeLoadID == loadID, !Task.isCancelled else { return }
        defer {
            if activeLoadID == loadID {
                isLoading = false
                isLoadingMore = false
            }
        }

        do {
            let account = await currentAccount()
            let session = currentSessionID()
            guard activeLoadID == loadID else { return }
            try Task.checkCancellation()
            let usesApp = defaults.object(forKey: RecommendationFilter.appRecommendKey) as? Bool ?? true
            let source: RecommendationRequest.Source = usesApp ? .app : .web
            if loadedAccount != account || cursorSession != session || cursorSource != source {
                appRefreshCursor = 0
                nextRequest = nil
            }
            loadedAccount = account
            cursorSession = session
            cursorSource = source
            let request: RecommendationRequest
            if reason == .loadMore {
                guard let nextRequest else { return }
                request = nextRequest
            } else {
                pendingRefresh = nil
                request = RecommendationRequest(source: source,
                    appCursor: reason == .refresh && usesApp ? appRefreshCursor : 0,
                    isRefresh: reason == .refresh)
            }
            try Task.checkCancellation()
            let response = try await fetchRecommendations(request)
            guard activeLoadID == loadID, !Task.isCancelled, currentSessionID() == session else { return }
            // 即使这一页全被过滤或去重，仍以原始响应推进；过期请求不能写回游标。
            nextRequest = response.nextRequest
            exposurePolicy = response.exposurePolicy ?? .init()
            let newBatch = response.videos
            guard !newBatch.isEmpty else { return }

            switch reason {
            case .refresh:
                if stageNextRefresh {
                    pendingRefresh = (newBatch, response.refreshCursor, session, source)
                } else {
                    applyRefresh(newBatch)
                    appRefreshCursor = response.refreshCursor ?? 0
                }
            case .initial, .loadMore:
                let wasEmpty = videos.isEmpty
                appendUnique(newBatch)
                if wasEmpty, !videos.isEmpty { appRefreshCursor = response.refreshCursor ?? 0 }
            }
        } catch {
            guard activeLoadID == loadID, !Self.isCancellation(error) else { return }
            // 与 PiliPlus 一致：已有推荐时刷新失败也保留旧内容，不把页面替换成错误页。
            errorMessage = error.localizedDescription
        }
    }

    /// 复刻 PiliPlus 的保留刷新：新内容放在上面，旧内容接在提示卡之后。
    /// 旧列表超过 200 条时只保留前 50 条，避免连续刷新让内存无限增长。
    /// 两项都可以在推荐流设置里关掉：不保留就整页换新，不提示就不插提示卡。
    private func applyRefresh(_ batch: [VideoSummary]) {
        let newVideos = Self.removingDuplicates(from: batch)
        guard !newVideos.isEmpty else { return }

        let keepsLastData = defaults.object(forKey: RecommendationFilter.keepLastDataKey) as? Bool ?? true
        guard keepsLastData, !videos.isEmpty else {
            videos = newVideos
            lastRefreshAt = nil
            return
        }

        let keepCount = videos.count > 200 ? 50 : videos.count
        let newIDs = Set(newVideos.map(\.bvid))
        let previousVideos = videos.prefix(keepCount).filter { !newIDs.contains($0.bvid) }

        videos = newVideos + previousVideos
        let showsTip = defaults.object(forKey: RecommendationFilter.lastSeenTipKey) as? Bool ?? true
        lastRefreshAt = previousVideos.isEmpty || !showsTip ? nil : newVideos.count
    }

    /// 分页只追加尚未出现的视频，避免重复 bvid 破坏 SwiftUI 卡片标识。
    private func appendUnique(_ batch: [VideoSummary]) {
        let existingIDs = Set(videos.map(\.bvid))
        let uniqueBatch = Self.removingDuplicates(from: batch)
            .filter { !existingIDs.contains($0.bvid) }
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
