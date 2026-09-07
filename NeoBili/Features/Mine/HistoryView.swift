import SwiftUI

/// 观看历史，游标翻页。
///
/// 结构与首页保持同构（ScrollView + 卡片 Button + 转场源直接挂在
/// Button 上），这样点开/退出视频页的 zoom 动效和首页完全一致。
struct HistoryView: View {
    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.videoTransitionNamespace) private var videoTransition
    @Environment(\.hidesPortraitVideos) private var hidesPortraitVideos

    @State private var items: [HistoryItem] = []
    @State private var cursorMax = 0
    @State private var cursorViewAt = 0
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    /// 正在走移除动效的条目。第一段淡出靠它驱动，见 `delete`。
    @State private var removals = ListRemovalState<String>()
    @State private var loadID = UUID()
    @State private var entranceGeneration = 0

    private var visibleItems: [HistoryItem] {
        items.hidingKnownPortraitVideos(hidesPortraitVideos)
    }

    var body: some View {
        Group {
            if visibleItems.isEmpty, items.hasPendingVideoDimensions(hidesPortraitVideos) {
                LoadingTaskAnchor()
            } else if let errorMessage, items.isEmpty {
                ContentUnavailableView {
                    Label("历史加载失败", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { Task { await reload() } }
                }
            } else if !hasMore, visibleItems.isEmpty {
                ContentUnavailableView(
                    items.isEmpty ? "还没有观看记录" : "没有可显示的视频",
                    systemImage: items.isEmpty ? "clock.arrow.circlepath" : "rectangle.slash"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleItems) { item in
                            row(item)
                        }
                        if visibleItems.isEmpty, hasMore, !isLoadingMore {
                            Button("继续加载") { Task { await loadNextPage() } }
                                .padding(.vertical, 12)
                                .disabled(isLoading)
                        }
                        if isLoadingMore {
                            LoadingTaskAnchor()
                                .padding(.vertical, 12)
                        }
                        if let errorMessage, !items.isEmpty {
                            VStack(spacing: 8) {
                                Text(errorMessage).font(.footnote).foregroundStyle(.secondary)
                                Button("重试加载") { Task { await loadNextPage() } }
                                    .disabled(isLoading || isLoadingMore)
                            }
                            .padding()
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
            if isLoading, items.isEmpty { LoadingTaskAnchor() }
        }
        .refreshable { await reload() }
        .task { await loadIfNeeded() }
        .resolvePortraitVideos(items, batchID: entranceGeneration) {
            guard hasMore, errorMessage == nil else { return items }
            await loadNextPage()
            return items
        }
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
                durationText: summary?.formattedDuration ?? "",
                animatesEntrance: false
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
        .cardFadeOut(isRemoving: removals.hiddenIDs.contains(item.id))
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
        let requestID = UUID()
        loadID = requestID
        let revision = removals.revision
        isLoading = true
        isLoadingMore = false
        defer { if loadID == requestID { isLoading = false } }
        do {
            let payload = try await BiliAPI.historyPage(max: 0, viewAt: 0)
            guard loadID == requestID, removals.revision == revision, !Task.isCancelled else { return }
            let incoming = payload.allItems.filter(\.isVideo)
            entranceGeneration += 1
            items = incoming.filter { !removals.hiddenIDs.contains($0.id) }

            if let cursor = payload.cursor, let nextMax = cursor.max, nextMax > 0, !incoming.isEmpty {
                cursorMax = nextMax
                cursorViewAt = cursor.resolvedViewAt ?? 0
                hasMore = true
            } else {
                hasMore = false
            }
            errorMessage = nil
        } catch {
            guard loadID == requestID, removals.revision == revision, !error.isCancellation else { return }
            if items.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    private func loadMoreIfNeeded(current item: HistoryItem) async {
        guard hasMore, !isLoadingMore, !isLoading, errorMessage == nil else { return }
        guard visibleItems.suffix(5).contains(where: { $0.id == item.id }) else { return }
        await loadNextPage()
    }

    private func loadNextPage() async {
        guard !isLoadingMore, !isLoading else { return }
        let requestID = UUID()
        loadID = requestID
        let revision = removals.revision
        errorMessage = nil
        isLoading = items.isEmpty
        isLoadingMore = !items.isEmpty
        defer {
            if loadID == requestID {
                isLoading = false
                isLoadingMore = false
            }
        }
        do {
            let payload = try await BiliAPI.historyPage(max: cursorMax, viewAt: cursorViewAt)
            guard loadID == requestID, removals.revision == revision, !Task.isCancelled else { return }
            let incoming = payload.allItems.filter(\.isVideo)
            let existing = Set(items.map(\.id))
            items.append(contentsOf: incoming.filter { !existing.contains($0.id) && !removals.hiddenIDs.contains($0.id) })

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
            guard loadID == requestID, removals.revision == revision, !error.isCancellation else { return }
            errorMessage = error.localizedDescription
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
        guard items.contains(where: { $0.id == item.id }), removals.begin(item.id) else { return }
        defer { removals.finish(item.id) }
        var removedIndex: Int?
        do {
            try await Task.sleep(for: .milliseconds(CardRemovalAnimation.menuDismissWaitMilliseconds))
            withAnimation(CardRemovalAnimation.fade) { removals.hide(item.id) }
            try await Task.sleep(for: .milliseconds(CardRemovalAnimation.fadeMilliseconds))
            withAnimation(CardRemovalAnimation.collapse) {
                removedIndex = removals.remove(item.id, from: &items)
            }
            try await BiliAPI.deleteHistory(kid: item.kidParam)
            // 同时完成的刷新也不能留下同 ID 的旧条目。
            withAnimation { items.removeAll { $0.id == item.id } }
            try? await Task.sleep(for: .milliseconds(CardRemovalAnimation.collapseMilliseconds))
        } catch {
            if let removedIndex {
                withAnimation { removals.restore(item, at: removedIndex, in: &items) }
            }
            if !error.isCancellation { feedback.show(error.localizedDescription) }
        }
    }
}
