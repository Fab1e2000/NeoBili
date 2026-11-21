#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI

/// 观看历史按游标分页；转场源挂在每张卡片的 Button 上。
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

    @State private var model = HistoryListModel()
    @State private var refresh = ListRefreshController()
    @State private var filterMemo = FilteredVideosMemo<HistoryItem>()
    @State private var menuRegistry = ResolvedMenuRegistry<String>()

    private var visibleItems: [HistoryItem] {
        filterMemo.videos(model.items, revision: model.contentRevision,
                          hidesPortraitVideos: hidesPortraitVideos, filtering: filtering)
    }

    var body: some View {
        let visibleItems = visibleItems
        let paginationIDs = Set(visibleItems.suffix(5).map(\.id))
        Group {
            if visibleItems.isEmpty, model.items.hasPendingVideoDimensions(hidesPortraitVideos, filtering: filtering) {
                LoadingTaskAnchor()
            } else if let errorMessage = model.errorMessage, model.items.isEmpty {
                ContentUnavailableView {
                    Label("历史加载失败", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { Task { await model.reload(services: services) } }
                }
            } else if !model.hasMore, visibleItems.isEmpty {
                ContentUnavailableView(
                    model.items.isEmpty ? "还没有观看记录" : "没有可显示的视频",
                    systemImage: model.items.isEmpty ? "clock.arrow.circlepath" : "rectangle.slash"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleItems) { item in
                            row(item, loadsNextPage: paginationIDs.contains(item.id))
                                .removalFillTransition()
                        }
                        if model.hasMore, !model.isLoadingMore, model.errorMessage == nil {
                            Button("继续加载") { Task { await model.loadNextPage(services: services, refreshing: refresh.isRefreshing) } }
                                .padding(.vertical, 12)
                                .disabled(model.isLoading)
                        }
                        if model.isLoadingMore {
                            LoadingTaskAnchor()
                                .padding(.vertical, 12)
                        }
                        if let errorMessage = model.errorMessage, !model.items.isEmpty {
                            InlineLoadFailure(title: "无法加载更多历史记录", message: errorMessage,
                                              isRetryDisabled: model.isLoading || model.isLoadingMore) {
                                Task { await model.loadNextPage(services: services, refreshing: refresh.isRefreshing) }
                            }
                        }
                    }
                    .background {
                        ResolvedMenuInstaller(registry: menuRegistry, menu: rowMenu)
                    }
                    // 删除看源列表的身份：过滤只改可见行，不触发补位。翻页是末尾追加，同样不动画。
                    .removalFill(ids: model.items.map(\.id), enabled: animatesExit, scope: .removalAndInlineRestore)
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
            if model.isLoading, model.items.isEmpty { LoadingTaskAnchor() }
        }
        .task { await model.loadIfNeeded(services: services) }
        .listEntrance(ids: visibleItems.map { "history:\($0.id)" }, generation: model.entranceGeneration, source: .history)
        .onDisappear { refresh.reset(discard: model.discardStagedPage) }
        .resolvePortraitVideos(model.items, batchID: model.entranceGeneration) {
            guard model.hasMore, model.errorMessage == nil else { return model.items }
            await model.loadNextPage(services: services, refreshing: refresh.isRefreshing)
            return model.items
        }
        .videoCardAnimationSource(.history)
        .safeAreaInset(edge: .bottom) {
            if model.isSelecting {
                LibrarySelectionBar(count: model.selectedIDs.count,
                    isBusy: model.isRemovingSelected || model.isLoading || model.isLoadingMore || refresh.isRefreshing,
                    done: { model.isSelecting = false; model.selectedIDs = [] }) {
                    Task { await model.removeSelected(services: services, account: account, feedback: feedback, refreshing: refresh.isRefreshing) }
                }
            }
        }
        .onChange(of: account.sessionID) { _, _ in
            model.reset()
            refresh.reset(discard: model.discardStagedPage)
            Task { await model.reload(services: services) }
        }
    }

    private func row(_ item: HistoryItem, loadsNextPage: Bool) -> some View {
        let summary = item.asVideoSummary

        return LibraryVideoCardButton(
            id: item.id, registry: menuRegistry,
            isSelecting: model.isSelecting, isSelected: model.selectedIDs.contains(item.id)
        ) {
            if model.isSelecting {
                guard !model.isRemovingSelected else { return }
                if model.selectedIDs.contains(item.id) { model.selectedIDs.remove(item.id) }
                else { model.selectedIDs.insert(item.id) }
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
            VideoListCard(
                coverURL: summary?.secureCoverURL,
                title: item.displayTitle,
                author: item.authorName ?? "",
                playCount: -1,
                durationText: summary?.formattedDuration ?? ""
            )
            .videoEntranceIdentity("history:\(item.id)")
        }
        .videoTransitionSource("history-\(summary?.bvid ?? "")", in: videoTransition)
        .padding(.horizontal, VideoListCardLayout.pageHorizontalInset)
        .padding(.vertical, VideoListCardLayout.cardVerticalSpacing)
        .task {
            if loadsNextPage { await model.loadMoreIfNeeded(services: services, refreshing: refresh.isRefreshing) }
            if !model.isSelecting, let summary {
                await preparation.prefetchWhenSettled(
                    bvid: summary.bvid,
                    cid: summary.cid > 0 ? summary.cid : nil
                )
            }
        }
    }

    private func rowMenu(for id: String) -> UIMenu {
        let busy = model.isRemovingSelected || model.isLoading || model.isLoadingMore || model.removals.hasPending || refresh.isRefreshing
        var actions: [UIAction] = []
        if !model.isSelecting {
            actions.append(menuRegistry.action("多选", systemImage: "checkmark.circle", enabled: !busy, id: id) { target in
                model.isSelecting = true
                model.selectedIDs = [target]
            })
        }
        actions.append(menuRegistry.action("稍后再看", systemImage: "flag", id: id) { target in
            guard let item = model.items.first(where: { $0.id == target }) else { return }
            WatchLaterAction.add(aid: item.asVideoSummary?.aid, bvid: item.asVideoSummary?.bvid,
                                 services: services, account: account, feedback: feedback)
        })
        actions.append(menuRegistry.action("删除这条历史", systemImage: "trash", destructive: true, enabled: !busy, id: id) { target in
            guard let item = model.items.first(where: { $0.id == target }) else { return }
            Task { await model.delete(item, services: services, account: account, feedback: feedback, refreshing: refresh.isRefreshing) }
        })
        return UIMenu(children: actions)
    }

    private var animatesExit: Bool { !reduceMotion && animations.isEnabled(phase: .exit) }

    private var canRefresh: Bool {
        !refresh.isRefreshing && !model.isLoading && !model.isLoadingMore && !model.removals.hasPending && !model.isRemovingSelected
    }

    /// 手动下拉刷新：旧卡片淡出的同时取第一页，两者都结束后一次换入。
    private func startRefresh() {
        guard canRefresh else { return }
        refresh.start(hasContent: !model.items.isEmpty, animatesExit: animatesExit, source: .history,
                      fetch: { await model.stageReload(services: services, feedback: feedback) },
                      commit: model.commitStagedReload,
                      discard: model.discardStagedPage)
    }

}
