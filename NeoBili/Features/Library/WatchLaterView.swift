import SwiftUI

/// 按官方 v2 游标分页加载；批量操作只覆盖明确选中的条目。
/// 卡片沿用搜索页/相关视频页的 `VideoListCard`，结构与首页同构
/// （ScrollView + Button + 转场源紧跟 buttonStyle），zoom 动效和首页一致。
struct WatchLaterView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(AccountStore.self) private var account
    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.videoTransitionNamespace) private var videoTransition
    @Environment(\.hidesPortraitVideos) private var hidesPortraitVideos

    private let isTabRoot: Bool
    private let onLayout: (([String: CGRect]) -> Void)?
    @State private var model: WatchLaterModel

    init(model: WatchLaterModel = WatchLaterModel(), isTabRoot: Bool = false, onLayout: (([String: CGRect]) -> Void)? = nil) {
        self.isTabRoot = isTabRoot
        self.onLayout = onLayout
        _model = State(initialValue: model)
    }

    private var items: [WatchLaterItem] { model.items }
    private var isLoading: Bool { model.isLoading }
    private var errorMessage: String? { model.errorMessage }

    private var visibleItems: [WatchLaterItem] {
        items.hidingKnownPortraitVideos(hidesPortraitVideos)
    }

    var body: some View {
        let visibleItems = visibleItems
        let paginationIDs = Set(visibleItems.suffix(5).map(\.id))
        Group {
            if visibleItems.isEmpty, items.hasPendingVideoDimensions(hidesPortraitVideos) {
                LoadingTaskAnchor()
                    .scrollingPageHeaderAbove()
            } else if let errorMessage, items.isEmpty {
                ContentUnavailableView {
                    Label("稍后再看加载失败", systemImage: "flag.slash")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试") { Task { await model.load(refresh: true) } }
                }
                .scrollingPageHeaderAbove()
            } else if !isLoading, visibleItems.isEmpty, !model.hasMore {
                ContentUnavailableView(
                    items.isEmpty ? "稍后再看是空的" : "没有可显示的视频",
                    systemImage: items.isEmpty ? "flag.checkered" : "rectangle.slash"
                )
                .scrollingPageHeaderAbove()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ScrollingPageHeaderRow()
                        ForEach(visibleItems) { item in row(item, loadsNextPage: paginationIDs.contains(item.id)) }
                        if model.hasMore || model.errorMessage != nil {
                            paginationFooter
                        }
                    }
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .tracksPageHeaderPull()
            }
        }
        // 左缘一小条是触控死区：点击不生效，避免滑动返回时误触卡片。
        .leftEdgeTapDeadZone()
        .navigationTitle("稍后再看")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoading, items.isEmpty { LoadingTaskAnchor() }
        }
        .refreshable { await model.load(refresh: true) }
        .task(id: account.sessionID) { await model.loadInitial() }
        .resolvePortraitVideos(items, batchID: items.count)
        .videoCardAnimationSource(.watchLater)
        .onPreferenceChange(WatchLaterLayoutFrames.self) { onLayout?($0) }
        .toolbar {
            if !isTabRoot {
                ToolbarItem(placement: .topBarTrailing) { selectionButton }
            }
        }

        .safeAreaInset(edge: .bottom) {
            if model.isSelecting {
                LibrarySelectionBar(count: model.selectedIDs.count,
                    isBusy: model.isRemoving || isLoading, done: endSelection) {
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
        .disabled(items.isEmpty || model.isRemoving || isLoading)
        .accessibilityIdentifier("watchlater.select")
    }

    private func endSelection() {
        model.isSelecting = false
        model.selectedIDs = []
    }

    private func row(_ item: WatchLaterItem, loadsNextPage: Bool) -> some View {
        let summary = item.asVideoSummary

        return Button {
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
            HStack(spacing: 8) {
                if model.isSelecting {
                    Image(systemName: model.selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(model.selectedIDs.contains(item.id) ? Color.accentColor : .secondary)
                        .font(.title2)
                }
                if dynamicTypeSize.isAccessibilitySize {
                    accessibleCard(item, summary: summary)
                } else {
                    VideoListCard(
                coverURL: summary?.secureCoverURL,
                title: item.title,
                author: item.upper?.name ?? "",
                playCount: -1,
                durationText: summary?.formattedDuration ?? "",
                animatesEntrance: false
                    )
                }
            }
            .background(layoutProbe("card-\(item.id)"))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(model.selectedIDs.contains(item.id) ? .isSelected : [])
        .contextMenu {
            if !model.isSelecting {
                Button {
                    model.isSelecting = true
                    model.selectedIDs = [item.id]
                } label: {
                    Label("多选", systemImage: "checkmark.circle")
                }
                .disabled(model.isRemoving || isLoading)
                .accessibilityIdentifier("watchlater.multiSelect")
            }
            Button(role: .destructive) {
                Task { await remove(ids: [item.id]) }
            } label: {
                Label("移出稍后再看", systemImage: "flag.slash")
            }
        }
        // 与首页完全同款的转场源挂载（紧跟 buttonStyle）。前缀避免与首页
        // 同一视频的转场源在共享命名空间里撞 id。
        //
        // 已知系统问题（iOS 26/27，摘掉转场源也复现）：A 的长按菜单还在
        // 退场时立刻长按 B，弹出的胶囊还是 A 的菜单项，点「移出」删掉的是
        // A。应用侧无法分辨菜单归属，只能等菜单完全收起再长按下一张卡。
        .videoTransitionSource("wl-\(summary?.bvid ?? "")", in: videoTransition)
        // 移除动效第一段：原地淡出、占位不变，列表此时不动。
        .padding(.horizontal, VideoListCardLayout.pageHorizontalInset)
        .padding(.vertical, VideoListCardLayout.cardVerticalSpacing)
        .task {
            if loadsNextPage, !model.isSelecting, model.errorMessage == nil { await model.load() }
            if !model.isSelecting, let summary {
                await VideoPreparationCache.shared.prefetchWhenSettled(
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
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .background(layoutProbe("title-\(item.id)"))
            Text(item.upper?.name ?? "")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .background(layoutProbe("author-\(item.id)"))
            Label(summary?.formattedDuration ?? "", systemImage: "clock")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .background(layoutProbe("duration-\(item.id)"))
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 7))
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
                VStack {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                    Button("重试") { Task { await model.load() } }
                }
            } else if model.isLoading {
                ProgressView()
            } else {
                Button("加载更多") { Task { await model.load() } }
            }
        }
        .padding()
    }

    private func remove(ids: Set<Int>) async {
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
