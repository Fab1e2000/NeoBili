import SwiftUI

/// 观看历史，游标翻页。
///
/// 结构与首页保持同构（ScrollView + 卡片 Button + 转场源直接挂在
/// Button 上），这样点开/退出视频页的 zoom 动效和首页完全一致。
struct HistoryView: View {
    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.videoTransitionNamespace) private var videoTransition

    @State private var items: [HistoryItem] = []
    @State private var cursorMax = 0
    @State private var cursorViewAt = 0
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    /// 正在走移除动效的条目。第一段淡出靠它驱动，见 `delete`。
    @State private var removingIDs: Set<String> = []

    var body: some View {
        Group {
            if let errorMessage, items.isEmpty {
                ContentUnavailableView {
                    Label("历史加载失败", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { Task { await reload() } }
                }
            } else if !hasMore, items.isEmpty {
                ContentUnavailableView("还没有观看记录", systemImage: "clock.arrow.circlepath")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            row(item)
                        }
                        if isLoadingMore {
                            ProgressView()
                                .padding(.vertical, 12)
                        }
                    }
                }
                .background(Color(uiColor: .systemGroupedBackground))
            }
        }
        // 左缘一小条是触控死区：点击不生效，避免滑动返回时误触卡片。
        .leftEdgeTapDeadZone()
        .navigationTitle("历史记录")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading, items.isEmpty { ProgressView() }
        }
        .refreshable { await reload() }
        .task { await loadIfNeeded() }
    }

    private func row(_ item: HistoryItem) -> some View {
        let summary = item.asVideoSummary

        return Button {
            guard let summary else { return }
            // 历史自带 cid，可直接并行取详情和播放地址；缺 cid 的条目传 nil 让详情页补。
            nowPlaying.open(
                VideoDetailRoute(
                    bvid: summary.bvid,
                    cid: summary.cid > 0 ? summary.cid : nil,
                    cover: summary.pic,
                    title: summary.title,
                    artist: summary.owner.name
                ),
                from: "history-\(summary.bvid)"
            )
        } label: {
            VideoListCard(
                coverURL: summary?.secureCoverURL,
                title: item.displayTitle,
                author: item.authorName ?? "",
                playCount: -1,
                durationText: summary?.formattedDuration ?? ""
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            WatchLaterMenuButton(aid: summary?.aid, bvid: summary?.bvid)

            Button(role: .destructive) {
                Task { await delete(item) }
            } label: {
                Label("删除这条历史", systemImage: "trash")
            }
        }
        // 与首页完全同款的转场源挂载（紧跟 buttonStyle）。前缀避免与首页
        // 同一视频的转场源在共享命名空间里撞 id。
        .videoTransitionSource("history-\(summary?.bvid ?? "")", in: videoTransition)
        // 移除动效第一段：原地淡出、占位不变，列表此时不动。
        .cardFadeOut(isRemoving: removingIDs.contains(item.id))
        .padding(.horizontal, VideoListCardLayout.pageHorizontalInset)
        .padding(.vertical, VideoListCardLayout.cardVerticalSpacing)
        .task {
            await loadMoreIfNeeded(current: item)
            if let summary {
                await VideoPreparationCache.shared.prefetch(
                    bvid: summary.bvid,
                    cid: summary.cid > 0 ? summary.cid : nil
                )
            }
        }
    }

    private func loadIfNeeded() async {
        guard items.isEmpty, !isLoading else { return }
        await reload()
    }

    /// 下拉刷新和「重试」都走这里。
    ///
    /// 同 `FavoriteFolderView.reload`：**不要**先清空 `items`。列表内容一变，
    /// SwiftUI 持有的下拉刷新任务就被取消，请求跟着失败，页面报「加载失败」；
    /// 而「重试」是另起的任务，不受影响，所以看起来只有下拉会坏。
    private func reload() async {
        isLoading = items.isEmpty
        defer { isLoading = false }
        do {
            let payload = try await BiliAPI.historyPage(max: 0, viewAt: 0)
            let incoming = payload.allItems.filter(\.isVideo)
            items = incoming

            if let cursor = payload.cursor, let nextMax = cursor.max, nextMax > 0, !incoming.isEmpty {
                cursorMax = nextMax
                cursorViewAt = cursor.resolvedViewAt ?? 0
                hasMore = true
            } else {
                hasMore = false
            }
            errorMessage = nil
        } catch {
            guard !error.isCancellation else { return }
            if items.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    private func loadMoreIfNeeded(current item: HistoryItem) async {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        guard items.suffix(5).contains(where: { $0.id == item.id }) else { return }
        await loadNextPage()
    }

    private func loadNextPage() async {
        guard !isLoadingMore else { return }
        isLoading = items.isEmpty
        isLoadingMore = !items.isEmpty
        defer {
            isLoading = false
            isLoadingMore = false
        }
        do {
            let payload = try await BiliAPI.historyPage(max: cursorMax, viewAt: cursorViewAt)
            let incoming = payload.allItems.filter(\.isVideo)
            let existing = Set(items.map(\.id))
            items.append(contentsOf: incoming.filter { !existing.contains($0.id) })

            if let cursor = payload.cursor, let nextMax = cursor.max, nextMax > 0 {
                cursorMax = nextMax
                cursorViewAt = cursor.resolvedViewAt ?? 0
            } else {
                hasMore = false
            }
            if incoming.isEmpty {
                hasMore = false
            }
            errorMessage = nil
        } catch {
            guard !error.isCancellation else { return }
            if items.isEmpty { errorMessage = error.localizedDescription }
            hasMore = false
        }
    }

    /// 删除一条历史。
    ///
    /// 先把卡片移走，再发请求。原来是等接口回来才移，网络往返那几百毫秒里
    /// 卡片一直杵在那儿，看起来就是「点了没反应，过一会儿才消失」。
    /// 失败时按原位放回去并说明原因。
    ///
    /// 动效拆成两段顺序执行（`CardRemovalAnimation`）：先原地淡出，完全
    /// 看不见后空位才收拢、下方卡片上移补位——两段同时进行会出现叠影。
    private func delete(_ item: HistoryItem) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

        // 先等长按菜单退场快照掀开，否则淡出被盖在快照后面看不见。
        try? await Task.sleep(for: .milliseconds(CardRemovalAnimation.menuDismissWaitMilliseconds))
        withAnimation(CardRemovalAnimation.fade) { removingIDs.insert(item.id) }
        try? await Task.sleep(for: .milliseconds(CardRemovalAnimation.fadeMilliseconds))

        withAnimation(CardRemovalAnimation.collapse) { items.remove(at: index) }

        do {
            try await BiliAPI.deleteHistory(kid: item.kidParam)
            // 等退出转场走完再清标记，避免同 id 的卡片被残留标记隐藏。
            try? await Task.sleep(for: .milliseconds(CardRemovalAnimation.collapseMilliseconds))
            removingIDs.remove(item.id)
        } catch {
            removingIDs.remove(item.id)
            withAnimation { items.insert(item, at: min(index, items.count)) }
            feedback.show(error.localizedDescription)
        }
    }
}
