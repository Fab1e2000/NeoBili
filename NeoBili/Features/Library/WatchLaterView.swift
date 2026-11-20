#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI

/// 稍后再看按 v2 游标分页，批量操作只覆盖选中条目；转场源挂在卡片 Button 上。
struct WatchLaterView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AccountStore.self) private var account
    @Environment(\.videoPreparation) private var preparation
    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.videoTransitionNamespace) private var videoTransition
    @Environment(\.videoFiltering) private var filtering
    @Environment(\.hidesPortraitVideos) private var hidesPortraitVideos
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var animations = VideoCardAnimationPreferences(source: .watchLater)

    private let isTabRoot: Bool
    private let onLayout: (([String: CGRect]) -> Void)?
    @State private var model: WatchLaterModel
    @State private var refresh = ListRefreshController()
    @State private var menuRegistry = ResolvedMenuRegistry<Int>()
    @State private var filterMemo = FilteredVideosMemo<WatchLaterItem>()

    init(model: WatchLaterModel = WatchLaterModel(), isTabRoot: Bool = false, onLayout: (([String: CGRect]) -> Void)? = nil) {
        self.isTabRoot = isTabRoot
        self.onLayout = onLayout
        _model = State(initialValue: model)
    }

    private var items: [WatchLaterItem] { model.items }
    private var isLoading: Bool { model.isLoading }
    private var errorMessage: String? { model.errorMessage }

    private var visibleItems: [WatchLaterItem] {
        filterMemo.videos(items, revision: model.contentRevision,
                          hidesPortraitVideos: hidesPortraitVideos, filtering: filtering)
    }

    var body: some View {
        let visibleItems = visibleItems
        let paginationIDs = Set(visibleItems.suffix(5).map(\.id))
        Group {
            if visibleItems.isEmpty, items.hasPendingVideoDimensions(hidesPortraitVideos, filtering: filtering) {
                LoadingTaskAnchor()
            } else if let errorMessage, items.isEmpty {
                ContentUnavailableView {
                    Label("稍后再看加载失败", systemImage: "flag.slash")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { Task { await model.load(refresh: true) } }
                }
            } else if !isLoading, visibleItems.isEmpty, !model.hasMore, errorMessage == nil {
                ContentUnavailableView(
                    items.isEmpty ? "稍后再看是空的" : "没有可显示的视频",
                    systemImage: items.isEmpty ? "flag.checkered" : "rectangle.slash"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleItems) { item in
                            row(item, loadsNextPage: paginationIDs.contains(item.id))
                                .removalFillTransition()
                        }
                        if model.hasMore || model.errorMessage != nil {
                            paginationFooter
                        }
                    }
                    .background {
                        ResolvedMenuInstaller(registry: menuRegistry, menu: rowMenu)
                    }
                    // 删除看源列表的身份：过滤只改可见行，不触发补位。翻页是末尾追加，同样不动画。
                    .removalFill(ids: items.map(\.id), enabled: animatesExit, scope: .removalAndInlineRestore)
                    // 与推荐页一致：松手后旧卡片淡出，新内容到了再换入。
                    .opacity(animatesExit ? refresh.contentOpacity : 1)
                    .allowsHitTesting(refresh.contentOpacity == 1)
                    .background {
                        ListPullRefresh(enabled: !refresh.isRefreshing && !isLoading && !model.isRemoving,
                                        onRefresh: startRefresh)
                    }
                }
                .scrollBounceBehavior(.always, axes: .vertical)
                .accessibilityAction(named: "刷新稍后再看", startRefresh)
                .background(Color(uiColor: .systemGroupedBackground))
            }
        }
        // 左缘一小条是触控死区：点击不生效，避免滑动返回时误触卡片。
        .leftEdgeTapDeadZone()
        .navigationTitle("稍后再看")
        .overlay {
            if isLoading, items.isEmpty { LoadingTaskAnchor() }
        }
        .task(id: account.sessionID) { await model.loadInitial() }
        .listEntrance(ids: visibleItems.map { "wl:\($0.id)" }, generation: model.entranceGeneration, source: .watchLater)
        .onDisappear { refresh.reset(discard: model.discardStagedRefresh) }
        .onChange(of: account.sessionID) { refresh.reset(discard: model.discardStagedRefresh) }
        .resolvePortraitVideos(items, batchID: items.count)
        .videoCardAnimationSource(.watchLater)
        .onPreferenceChange(WatchLaterLayoutFrames.self) { onLayout?($0) }
        .toolbar {
            if !isTabRoot {
                // 从「我的服务」进入时右上角提供刷新；作为标签页挂载时只有下拉刷新。
                ToolbarItem(placement: .topBarTrailing) {
                    Button("刷新", systemImage: "arrow.clockwise", action: startRefresh)
                        .labelStyle(.iconOnly)
                        .disabled(!canRefresh)
                        .accessibilityIdentifier("watchlater.refresh")
                }
                ToolbarItem(placement: .topBarTrailing) { selectionButton }
            }
        }

        .safeAreaInset(edge: .bottom) {
            if model.isSelecting {
                LibrarySelectionBar(count: model.selectedIDs.count,
                    isBusy: model.isRemoving || isLoading || refresh.isRefreshing, done: endSelection) {
                    Task { await remove(ids: model.selectedIDs) }
                }
            }
        }
    }

    private var selectionButton: some View {
        Button(model.isSelecting ? String(localized: "完成") : String(localized: "选择")) {
            model.isSelecting.toggle()
            model.selectedIDs = []
        }
        .frame(minHeight: 44)
        .disabled(items.isEmpty || model.isRemoving || isLoading || refresh.isRefreshing)
        .accessibilityIdentifier("watchlater.select")
    }

    private var animatesExit: Bool { !reduceMotion && animations.isEnabled(phase: .exit) }

    private var canRefresh: Bool { !refresh.isRefreshing && !isLoading && !model.isRemoving }

    private func startRefresh() {
        guard canRefresh else { return }
        refresh.start(hasContent: !items.isEmpty, animatesExit: animatesExit, source: .watchLater,
                      fetch: { await model.stageRefresh() },
                      commit: model.commitStagedRefresh,
                      discard: model.discardStagedRefresh)
    }

    private func endSelection() {
        model.isSelecting = false
        model.selectedIDs = []
    }

    private func row(_ item: WatchLaterItem, loadsNextPage: Bool) -> some View {
        let summary = item.asVideoSummary

        return LibraryVideoCardButton(
            id: item.id, registry: menuRegistry,
            isSelecting: model.isSelecting, isSelected: model.selectedIDs.contains(item.id)
        ) {
            if model.isSelecting { model.toggle(item); return }
            guard let summary else { return }
            nowPlaying.open(
                VideoDetailRoute(
                    bvid: summary.bvid,
                    cid: summary.cid > 0 ? summary.cid : nil,
                    cover: summary.pic,
                    title: summary.title,
                    artist: summary.owner.name, aid: summary.aid, playbackEntry: .watchLater
                ),
                from: "wl-\(summary.bvid)"
            )
        } label: {
            if dynamicTypeSize.isAccessibilitySize {
                accessibleCard(item, summary: summary)
            } else {
                VideoListCard(
                    coverURL: summary?.secureCoverURL,
                    title: item.title,
                    author: item.upper?.name ?? "",
                    playCount: -1,
                    durationText: summary?.formattedDuration ?? ""
                )
                .videoEntranceIdentity("wl:\(item.id)")
            }
        }
        .background(layoutProbe("card-\(item.id)"))
        .videoTransitionSource("wl-\(summary?.bvid ?? "")", in: videoTransition)
        .padding(.horizontal, VideoListCardLayout.pageHorizontalInset)
        .padding(.vertical, VideoListCardLayout.cardVerticalSpacing)
        .task {
            if loadsNextPage, !model.isSelecting, model.errorMessage == nil { await model.load() }
            if !model.isSelecting, let summary {
                await preparation.prefetchWhenSettled(
                    bvid: summary.bvid,
                    cid: summary.cid > 0 ? summary.cid : nil
                )
            }
        }
    }

    private func accessibleCard(_ item: WatchLaterItem, summary: VideoSummary?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverThumbnail(url: summary?.secureCoverURL)
                .frame(maxWidth: 240)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            Text(item.title)
                .font(.app(.subheadline, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .background(layoutProbe("title-\(item.id)"))
            Text(item.upper?.name ?? "")
                .font(.app(.caption)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .background(layoutProbe("author-\(item.id)"))
            Label(summary?.formattedDuration ?? "", systemImage: "clock")
                .font(.app(.caption2)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .background(layoutProbe("duration-\(item.id)"))
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: VideoListCardLayout.cardCornerRadius, style: .continuous))
    }

    /// Geometry observation is injected only by rendering tests; normal scrolling has no probes.
    @ViewBuilder private func layoutProbe(_ key: String) -> some View {
        if onLayout != nil {
            GeometryReader { proxy in
                Color.clear.preference(key: WatchLaterLayoutFrames.self, value: [key: proxy.frame(in: .global)])
            }
        }
    }

    private var paginationFooter: some View {
        Group {
            if let error = model.errorMessage {
                InlineLoadFailure(title: model.failedRefresh ? "稍后再看未能刷新" : "无法加载更多稍后再看视频",
                                  message: error) {
                    Task { await model.load() }
                }
            } else if model.isLoading {
                ProgressView()
            } else {
                Button("加载更多") { Task { await model.load() } }
            }
        }
        .padding()
    }

    private func rowMenu(for id: Int) -> UIMenu {
        let busy = model.isRemoving || isLoading || refresh.isRefreshing
        var actions: [UIAction] = []
        if !model.isSelecting {
            actions.append(menuRegistry.action("多选", systemImage: "checkmark.circle", enabled: !busy, id: id) { target in
                model.isSelecting = true
                model.selectedIDs = [target]
            })
        }
        actions.append(menuRegistry.action("移出稍后再看", systemImage: "flag.slash", destructive: true, enabled: !busy, id: id) { target in
            Task { await remove(ids: [target]) }
        })
        return UIMenu(children: actions)
    }

    private func remove(ids: Set<Int>) async {
        guard !refresh.isRefreshing else { return }
        let error = await model.remove(ids: ids) {
            await feedback.confirmRemoval(String(localized: "已移出稍后再看"))
        }
        if let error { feedback.show(error) }
    }
}

private struct WatchLaterLayoutFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
