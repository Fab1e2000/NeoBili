#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI

/// 观看历史，游标翻页。
///
/// 结构与首页保持同构（ScrollView + 卡片 Button + 转场源直接挂在
/// Button 上），这样点开/退出视频页的 zoom 动效和首页完全一致。
struct HistoryView: View {
    /// 作为底部标签页的根页面挂载（不显示刷新按钮）。
    var isTabRoot = false
    @Environment(\.applicationServices) private var services
    @Environment(AccountStore.self) private var account
    @Environment(\.videoPreparation) private var preparation
    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.videoTransitionNamespace) private var videoTransition
    @Environment(\.videoFiltering) private var filtering
    @Environment(\.hidesPortraitVideos) private var hidesPortraitVideos
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var animations = VideoCardAnimationPreferences(source: .history)

    /// 手动刷新取回但还没换进列表的第一页。
    private struct StagedPage {
        let items: [HistoryItem]
        let hasMore: Bool
        let cursorMax: Int
        let cursorViewAt: Int
        /// 取回时的移除状态；换入前若又发生过移除，这份快照已过期。
        let revision: UUID
    }

    @State private var refresh = ListRefreshController()
    @State private var stagedPage: StagedPage?
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
    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var isRemovingSelected = false

    private var visibleItems: [HistoryItem] {
        items.hidingKnownPortraitVideos(hidesPortraitVideos, filtering: filtering)
    }

    var body: some View {
        let visibleItems = visibleItems
        let paginationIDs = Set(visibleItems.suffix(5).map(\.id))
        Group {
            if visibleItems.isEmpty, items.hasPendingVideoDimensions(hidesPortraitVideos, filtering: filtering) {
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
                            row(item, loadsNextPage: paginationIDs.contains(item.id))
                        }
                        if hasMore, !isLoadingMore {
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
                                Text(errorMessage).font(.app(.footnote)).foregroundStyle(.secondary)
                                Button("重试加载") { Task { await loadNextPage() } }
                                    .disabled(isLoading || isLoadingMore)
                            }
                            .padding()
                        }
                    }
                    // 与推荐页一致：松手后旧卡片淡出，新内容到了再换入。
                    .opacity(animatesExit ? refresh.contentOpacity : 1)
                    .allowsHitTesting(refresh.contentOpacity == 1)
                    .background {
                        ListPullRefresh(enabled: canRefresh, onRefresh: startRefresh)
                    }
                }
                .scrollBounceBehavior(.always, axes: .vertical)
                .accessibilityAction(named: "刷新历史记录", startRefresh)
                .background(Color(uiColor: .systemGroupedBackground))
            }
        }
        // 左缘一小条是触控死区：点击不生效，避免滑动返回时误触卡片。
        .leftEdgeTapDeadZone()
        .navigationTitle("历史记录")
        .toolbar {
            // 从「我的服务」进入时右上角提供刷新；作为标签页挂载时只有下拉刷新。
            if !isTabRoot {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("刷新", systemImage: "arrow.clockwise", action: startRefresh)
                        .labelStyle(.iconOnly)
                        .disabled(!canRefresh)
                        .accessibilityIdentifier("history.refresh")
                }
            }
        }
        .overlay {
            if isLoading, items.isEmpty { LoadingTaskAnchor() }
        }
        .task { await loadIfNeeded() }
        .listEntrance(ids: visibleItems.map { "history:\($0.id)" }, generation: entranceGeneration, source: .history)
        .onDisappear { refresh.reset(discard: { stagedPage = nil }) }
        .resolvePortraitVideos(items, batchID: entranceGeneration) {
            guard hasMore, errorMessage == nil else { return items }
            await loadNextPage()
            return items
        }
        .videoCardAnimationSource(.history)
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                LibrarySelectionBar(count: selectedIDs.count,
                    isBusy: isRemovingSelected || isLoading || isLoadingMore || refresh.isRefreshing,
                    done: { isSelecting = false; selectedIDs = [] }) {
                    Task { await removeSelected() }
                }
            }
        }
        .onChange(of: account.sessionID) { _, _ in
            loadID = UUID()
            items = []; selectedIDs = []; isSelecting = false
            isLoading = false; isLoadingMore = false
            isRemovingSelected = false
            removals = ListRemovalState()
            hasMore = true
            errorMessage = nil
            refresh.reset(discard: { stagedPage = nil })
            Task { await reload() }
        }
    }

    private func row(_ item: HistoryItem, loadsNextPage: Bool) -> some View {
        let summary = item.asVideoSummary

        return Button {
            if isSelecting {
                guard !isRemovingSelected else { return }
                if selectedIDs.contains(item.id) { selectedIDs.remove(item.id) }
                else { selectedIDs.insert(item.id) }
                return
            }
            guard let summary else { return }
            // 历史自带 cid，可直接并行取详情和播放地址；缺 cid 的条目传 nil 让详情页补。
            nowPlaying.open(
                VideoDetailRoute(
                    bvid: summary.bvid,
                    cid: summary.cid > 0 ? summary.cid : nil,
                    cover: summary.pic,
                    title: summary.title,
                    artist: summary.owner.name, aid: summary.aid, playbackEntry: .history
                ),
                from: "history-\(summary.bvid)"
            )
        } label: {
            HStack(spacing: 8) {
                if isSelecting {
                    Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        .font(.app(.title2))
                        .foregroundStyle(selectedIDs.contains(item.id) ? Color.accentColor : .secondary)
                }
            VideoListCard(
                coverURL: summary?.secureCoverURL,
                title: item.displayTitle,
                author: item.authorName ?? "",
                playCount: -1,
                durationText: summary?.formattedDuration ?? ""
            )
            .videoEntranceIdentity("history:\(item.id)")
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedIDs.contains(item.id) ? .isSelected : [])
        .contextMenu {
            if !isSelecting {
                Button {
                    isSelecting = true; selectedIDs = [item.id]
                } label: { Label("多选", systemImage: "checkmark.circle") }
                .disabled(isRemovingSelected || isLoading || isLoadingMore || removals.hasPending || refresh.isRefreshing)
            }
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
        .padding(.horizontal, VideoListCardLayout.pageHorizontalInset)
        .padding(.vertical, VideoListCardLayout.cardVerticalSpacing)
        .task {
            if loadsNextPage { await loadMoreIfNeeded() }
            if !isSelecting, let summary {
                await preparation.prefetchWhenSettled(
                    bvid: summary.bvid,
                    cid: summary.cid > 0 ? summary.cid : nil
                )
            }
        }
    }

    private func removeSelected() async {
        guard !isRemovingSelected, !isLoading, !isLoadingMore, !removals.hasPending, !refresh.isRefreshing else { return }
        let snapshot = items
        let targets = snapshot.filter { selectedIDs.contains($0.id) }
        guard !targets.isEmpty else { return }
        let owner = account.sessionID
        let identitySession = services.session.currentID()
        isRemovingSelected = true
        loadID = UUID()
        for target in targets { _ = removals.begin(target.id); removals.hide(target.id) }
        defer {
            if account.sessionID == owner {
                for target in targets { removals.finish(target.id) }
                isRemovingSelected = false
            }
        }
        let lookup = Dictionary(targets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ids = Set(targets.map(\.id))
        items.removeAll { ids.contains($0.id) }
        let result = await LibraryBatchRemoval.perform(ids: targets.map(\.id),
            isCurrent: { account.sessionID == owner },
            confirm: { await feedback.confirmRemoval(String(localized: "已移除历史记录")) },
            remove: { id in
                guard let target = lookup[id] else { return }
                try await services.library.deleteHistory(kid: target.kidParam, expectedSessionID: identitySession)
            })
        guard account.sessionID == owner else { return }
        items = snapshot.filter { !result.succeeded.contains($0.id) }
        selectedIDs.subtract(result.succeeded)
        if selectedIDs.isEmpty { isSelecting = false }
        if let error = result.error { feedback.show(error) }
    }

    private func loadIfNeeded() async {
        guard items.isEmpty, !isLoading else { return }
        await reload()
    }

    private var animatesExit: Bool { !reduceMotion && animations.isEnabled(phase: .exit) }

    private var canRefresh: Bool {
        !refresh.isRefreshing && !isLoading && !isLoadingMore && !removals.hasPending && !isRemovingSelected
    }

    /// 手动下拉刷新：旧卡片淡出的同时取第一页，两者都结束后一次换入。
    private func startRefresh() {
        guard canRefresh else { return }
        refresh.start(hasContent: !items.isEmpty, animatesExit: animatesExit, source: .history,
                      fetch: { await stageReload() },
                      commit: commitStagedReload,
                      discard: { stagedPage = nil })
    }

    private func stageReload() async -> Bool {
        let requestID = UUID()
        loadID = requestID
        let revision = removals.revision
        stagedPage = nil
        isLoading = true
        defer { if loadID == requestID { isLoading = false } }
        do {
            let payload = try await services.library.historyPage(max: 0, viewAt: 0)
            guard loadID == requestID, removals.revision == revision, !Task.isCancelled else { return false }
            stagedPage = StagedPage(
                items: LibraryPageRules.unique(payload.allItems.filter(\.isVideo), excluding: removals.hiddenIDs),
                hasMore: LibraryPageRules.advancesHistory(max: payload.cursor?.max,
                    viewAt: payload.cursor?.resolvedViewAt, fromMax: 0, fromViewAt: 0),
                cursorMax: payload.cursor?.max ?? 0,
                cursorViewAt: payload.cursor?.resolvedViewAt ?? 0,
                revision: revision)
            return true
        } catch {
            guard loadID == requestID, removals.revision == revision, !error.isCancellation else { return false }
            feedback.show(error.localizedDescription)
            return false
        }
    }

    private func commitStagedReload() {
        guard let page = stagedPage else { return }
        stagedPage = nil
        guard page.revision == removals.revision, !removals.hasPending else { return }
        entranceGeneration += 1
        items = page.items
        selectedIDs.formIntersection(Set(items.map(\.id)))
        if selectedIDs.isEmpty { isSelecting = false }
        hasMore = page.hasMore
        cursorMax = page.cursorMax
        cursorViewAt = page.cursorViewAt
        errorMessage = nil
    }

    /// 首次加载和「重试」走这里；手动下拉刷新走 `startRefresh`。
    private func reload() async {
        guard !removals.hasPending, !isRemovingSelected else { return }
        let requestID = UUID()
        loadID = requestID
        let revision = removals.revision
        isLoading = true
        isLoadingMore = false
        defer { if loadID == requestID { isLoading = false } }
        do {
            let payload = try await services.library.historyPage(max: 0, viewAt: 0)
            guard loadID == requestID, removals.revision == revision, !Task.isCancelled else { return }
            let incoming = payload.allItems.filter(\.isVideo)
            entranceGeneration += 1
            items = LibraryPageRules.unique(incoming, excluding: removals.hiddenIDs)
            selectedIDs.formIntersection(Set(items.map(\.id)))

            hasMore = LibraryPageRules.advancesHistory(max: payload.cursor?.max,
                viewAt: payload.cursor?.resolvedViewAt, fromMax: 0, fromViewAt: 0)
            cursorMax = payload.cursor?.max ?? 0
            cursorViewAt = payload.cursor?.resolvedViewAt ?? 0
            errorMessage = nil
        } catch {
            guard loadID == requestID, removals.revision == revision, !error.isCancellation else { return }
            if items.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    private func loadMoreIfNeeded() async {
        guard !isSelecting, hasMore, !isLoadingMore, !isLoading, !refresh.isRefreshing, errorMessage == nil else { return }
        await loadNextPage()
    }

    private func loadNextPage() async {
        guard !removals.hasPending, !isRemovingSelected, !refresh.isRefreshing else { return }
        guard hasMore, !isLoadingMore, !isLoading else { return }
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
            let payload = try await services.library.historyPage(max: cursorMax, viewAt: cursorViewAt)
            guard loadID == requestID, removals.revision == revision, !Task.isCancelled else { return }
            let incoming = payload.allItems.filter(\.isVideo)
            let existing = Set(items.map(\.id))
            items.append(contentsOf: LibraryPageRules.unique(incoming, excluding: existing.union(removals.hiddenIDs)))

            hasMore = LibraryPageRules.advancesHistory(max: payload.cursor?.max,
                viewAt: payload.cursor?.resolvedViewAt, fromMax: cursorMax, fromViewAt: cursorViewAt)
            cursorMax = payload.cursor?.max ?? 0
            cursorViewAt = payload.cursor?.resolvedViewAt ?? 0
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
    /// 直接更新列表，保留撤销确认、账号校验和失败回滚。
    private func delete(_ item: HistoryItem) async {
        guard !isRemovingSelected, !refresh.isRefreshing, items.contains(where: { $0.id == item.id }), removals.begin(item.id) else { return }
        let sessionID = account.sessionID
        defer { if account.sessionID == sessionID { removals.finish(item.id) } }
        let identitySession = services.session.currentID()
        var removedIndex: Int?
        do {
            removals.hide(item.id)
            removedIndex = removals.remove(item.id, from: &items)
            guard await feedback.confirmRemoval(String(localized: "已移除历史记录")),
                  account.sessionID == sessionID, !Task.isCancelled else { throw CancellationError() }
            try await services.library.deleteHistory(kid: item.kidParam, expectedSessionID: identitySession)
            guard account.sessionID == sessionID else { return }
            // 同时完成的刷新也不能留下同 ID 的旧条目。
            items.removeAll { $0.id == item.id }
            selectedIDs.remove(item.id)
            if selectedIDs.isEmpty { isSelecting = false }
        } catch {
            if account.sessionID == sessionID, let removedIndex {
                removals.restore(item, at: removedIndex, in: &items)
            }
            if account.sessionID == sessionID, !error.isCancellation { feedback.show(error.localizedDescription) }
        }
    }
}
