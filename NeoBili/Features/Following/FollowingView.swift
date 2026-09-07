import SwiftUI

/// 「关注」Tab：动态流与可收起的侧边关注选择器。
struct FollowingView: View {
    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(AccountStore.self) private var account
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.videoTransitionNamespace) private var videoTransition
    @Environment(\.hidesPortraitVideos) private var hidesPortraitVideos
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel = FollowingViewModel()
    @State private var path: [FollowedUp] = []
    /// 正在看哪条动态的详情。有值时推入详情页。
    @Namespace private var dynamicTransition
    @State private var detailEntry: DynamicEntry?
    /// 轮盘拖动时的视觉焦点；只有停稳后才提交给 ViewModel。
    @State private var focusedTargetID: FollowingSelection.ID = .all
    @AppStorage(FollowingSidebarSide.storageKey) private var sidebarSide: FollowingSidebarSide = .left
    @AppStorage(FollowingSidebarDwellSettings.storageKey) private var sidebarDwellDuration = FollowingSidebarDwellSettings.defaultDuration
    @State private var isSidebarExpanded = false
    @State private var openingSwipeProgress: CGFloat?
    @State private var listPosition = ScrollPosition(edge: .top)
    @AppStorage(HomeRefreshSettings.storageKey) private var refreshDistance = HomeRefreshSettings.defaultDistance
    @AppStorage(AnimationSpeedSettings.exitSpeedKey) private var exitSpeed = AnimationSpeedSettings.defaultSpeed
    @AppStorage(AnimationSpeedSettings.enterSpeedKey) private var enterSpeed = AnimationSpeedSettings.defaultSpeed
    @State private var isRefreshing = false
    @State private var refreshOpacity = 1.0
    @State private var landingGeneration = 0
    @State private var landingWindow = false
    @State private var refreshTask: Task<Void, Never>?
    @State private var feedOpacity = 1.0
    @State private var selectionTransitionTask: Task<Void, Never>?
    @State private var pendingSelectionID: FollowingSelection.ID?
    @State private var isFollowingVisible = false

    var body: some View {
        NavigationStack(path: $path) {
            GeometryReader { geometry in
                Group {
                    if account.isLoggedIn {
                        feed
                    } else if account.isRestoringSession {
                        LoadingTaskAnchor()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        loggedOutView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // 用同一张页面底板覆盖上下安全区，侧边凹口在内容中线对齐头像。
                .background(alignment: .top) {
                    FollowingPageEdgeShape(
                        side: sidebarSide,
                        progress: sidebarExpansionProgress,
                        topInset: geometry.safeAreaInsets.top,
                        bottomInset: geometry.safeAreaInsets.bottom
                    )
                    .fill(Color(uiColor: .systemBackground))
                    .frame(width: geometry.size.width,
                           height: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom)
                    .offset(y: -geometry.safeAreaInsets.top)
                    .animation(sidebarTransition, value: isSidebarExpanded)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .background(Color(uiColor: .systemGroupedBackground))
            }
            .navigationTitle("关注")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: FollowedUp.self) { up in
                SpaceView(up: up)
            }
            .fullScreenCover(item: $detailEntry) { entry in
                NavigationStack {
                    DynamicDetailView(entry: entry, feed: viewModel.activeFeed)
                }
                .appTextSize()
                .actionFeedbackOverlay()
                .navigationTransition(.zoom(sourceID: "following-dynamic-\(entry.id)", in: dynamicTransition))
            }
            // 动态直接从安全区开始，侧边选择器不占据顶部空间。
            // 标题本身留着，推入 UP 主页时返回按钮才有「关注」这两个字。
            .toolbarVisibility(.hidden, for: .navigationBar)
            .imageViewerHost()
            // 关注流滚动时底部标签栏始终保留；进入子页面后由子页面自行隐藏。
            .tabBarMinimizeBehavior(.never)
            .onAppear {
                OrientationController.enterPortrait()
            }
        }
        .onChange(of: account.sessionID) {
            cancelRefreshAnimation()
            selectionTransitionTask?.cancel()
            path = []
            detailEntry = nil
            isSidebarExpanded = false
            focusedTargetID = .all
            feedOpacity = 1
            listPosition.scrollTo(edge: .top)
            viewModel = FollowingViewModel()
        }
        .resolvePortraitVideos(viewModel.activeFeed.entries.compactMap(\.video), batchID: landingGeneration) {
            let feed = viewModel.activeFeed
            await feed.loadReplacementPage()
            return feed.entries.compactMap(\.video)
        }
    }

    private var loggedOutView: some View {
        ContentUnavailableView {
            Label("尚未登录", systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            Text("登录后这里会显示你关注的 UP 主的最新动态。\n登录入口在「我的」页。")
        }
    }

    // MARK: - 已登录

    private var feed: some View {
        list
            .task(id: account.accountID) {
                FollowingReadStore.shared.configure(accountID: account.accountID)
                await viewModel.loadInitial()
            }

    }

    private var sidebarExpansionProgress: CGFloat {
        openingSwipeProgress ?? (isSidebarExpanded ? 1 : 0)
    }

    private var contentDisplacement: CGFloat {
        sidebarExpansionProgress * FollowingSidebarLayout.contentDisplacement * (sidebarSide == .left ? 1 : -1)
    }

    private var sidebarTransition: Animation? {
        reduceMotion || openingSwipeProgress != nil ? nil : .timingCurve(0.42, 0, 0.58, 1, duration: FollowingSidebarLayout.transitionDuration)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                feedContent.opacity(feedOpacity * refreshOpacity)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            // 手势观察器不参与纵向布局，避免独立零高占位产生默认间距。
            .background(alignment: .top) {
                ShortPullRefresh(
                    threshold: refreshDistance,
                    enabled: !isRefreshing && !isSidebarExpanded,
                    onProgress: { distance, _ in updatePullFade(distance) },
                    onRefresh: startRefresh
                )
                .overlay {
                    FollowingPageSwipeObserver(
                        enabled: !isSidebarExpanded || openingSwipeProgress != nil,
                        onMove: { translation in
                            openingSwipeProgress = min(max(translation / FollowingSidebarLayout.contentDisplacement, 0), 1)
                            if !isSidebarExpanded { isSidebarExpanded = true }
                        },
                        onEnd: { velocity in
                            guard let progress = openingSwipeProgress else { return }
                            let expanded = velocity.map { progress + $0 * 0.12 / FollowingSidebarLayout.contentDisplacement >= 0.5 } ?? false
                            let animation: Animation? = reduceMotion ? nil : .timingCurve(0.42, 0, 0.58, 1, duration: FollowingSidebarLayout.transitionDuration)
                            withAnimation(animation) {
                                openingSwipeProgress = nil
                                isSidebarExpanded = expanded
                            }
                        }
                    )
                }
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .scrollPosition($listPosition)
        // 即使内容不足一屏也允许下拉刷新。
        .scrollBounceBehavior(.always, axes: .vertical)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollDisabled(isRefreshing || pendingSelectionID != nil)
        .overlay(alignment: .top) {
            if pendingSelectionID != nil || (reduceMotion && isRefreshing) {
                LoadingTaskAnchor().controlSize(.small).padding(.top, 12)
            }
        }
        .accessibilityAction(named: "刷新关注动态") { startRefresh() }
        // 保持动态原有宽度和滚动位置，展开时整页为侧栏让出空间。
        .offset(x: contentDisplacement)
        .animation(sidebarTransition, value: isSidebarExpanded)
        // 左缘一小条是触控死区：点击不生效，避免滑动返回时误触卡片。
        .leftEdgeTapDeadZone()
        // 入口在死区外层，仍能从屏幕边缘直接点击和滑动。
        .overlay {
            FollowingCarousel(
                items: viewModel.carouselItems,
                focusedID: $focusedTargetID,
                side: sidebarSide,
                isExpanded: $isSidebarExpanded,
                onSettled: { id in
                    // 展开时由焦点停留计时触发，不让松手吸附提前提交。
                    if !isSidebarExpanded { settleSelection(id) }
                },
                onOpenUp: { path.append($0) },
                interactiveProgress: openingSwipeProgress,
                onCloseSwipe: { translation in
                    openingSwipeProgress = min(max(1 + translation / FollowingSidebarLayout.contentDisplacement, 0), 1)
                },
                onCloseSwipeEnd: { velocity in
                    let progress = openingSwipeProgress ?? 1
                    let expanded = progress + velocity * 0.12 / FollowingSidebarLayout.contentDisplacement >= 0.5
                    let animation: Animation? = reduceMotion ? nil : .timingCurve(0.42, 0, 0.58, 1, duration: FollowingSidebarLayout.transitionDuration)
                    withAnimation(animation) {
                        openingSwipeProgress = nil
                        isSidebarExpanded = expanded
                    }
                }
            )
        }
        .onAppear { isFollowingVisible = true }
        .task(id: isSidebarExpanded ? focusedTargetID : nil) {
            guard isSidebarExpanded else { return }
            let targetID = focusedTargetID
            if targetID == viewModel.selectedTarget.id {
                // 原头像不计时刷新；滑回原头像时取消尚未完成的切换。
                settleSelection(targetID)
                return
            }
            do {
                try await Task.sleep(for: .seconds(FollowingSidebarDwellSettings.clamped(sidebarDwellDuration)))
            } catch {
                return
            }
            guard !Task.isCancelled, isSidebarExpanded, focusedTargetID == targetID else { return }
            settleSelection(targetID, refresh: true)
        }
        .onChange(of: isSidebarExpanded) { _, expanded in
            if !expanded, isFollowingVisible {
                settleSelection(focusedTargetID)
            }
        }
        .onDisappear {
            isFollowingVisible = false
            openingSwipeProgress = nil
            cancelRefreshAnimation()
            isSidebarExpanded = false
            focusedTargetID = viewModel.selectedTarget.id
            selectionTransitionTask?.cancel()
            feedOpacity = 1
        }
    }

    @ViewBuilder
    private var feedContent: some View {
        let feed = viewModel.activeFeed

        if feed.isLoading, feed.entries.isEmpty {
            loadingPlaceholder
        } else if let message = feed.errorMessage, feed.entries.isEmpty {
            ContentUnavailableView {
                Label("加载失败", systemImage: "wifi.slash")
            } description: {
                Text(message)
            } actions: {
                Button("重试") {
                    Task { await viewModel.activeFeed.refresh() }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 300)
        } else if !feed.isLoading, feed.entries.isEmpty {
            ContentUnavailableView(
                "还没有新动态",
                systemImage: "bell.slash",
                description: Text(
                    viewModel.selectedUp == nil
                        ? "你关注的 UP 主最近没有更新。"
                        : "这位 UP 主最近没有更新。"
                )
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: 300)
        } else {
            let visibleEntries = feed.entries.filter { $0.video?.canDisplayVideo(hidingPortrait: hidesPortraitVideos) ?? true }
            if visibleEntries.isEmpty {
                if feed.entries.compactMap(\.video).hasPendingVideoDimensions(hidesPortraitVideos) {
                    LoadingTaskAnchor().padding()
                } else {
                    Button("继续加载动态") { Task { await feed.loadReplacementPage() } }
                        .padding()
                }
            }
            ForEach(Array(visibleEntries.enumerated()), id: \.element.id) { index, entry in
                FeedDropInRow(index: index, generation: landingGeneration,
                              landing: landingWindow, speed: enterSpeed, reduceMotion: reduceMotion) {
                    card(for: entry)
                }
                    .videoEntranceIdentity(entry.video?.bvid)
                    .onScrollVisibilityChange(threshold: 0.1) { visible in
                        if visible { FollowingReadStore.shared.markViewed(entry) }
                    }
                    .padding(.horizontal, DynamicCardLayout.pageHorizontalInset)
                    .padding(.vertical, DynamicCardLayout.cardVerticalSpacing)
                    .task { await feed.loadMoreIfNeeded(current: entry) }
                    .task {
                        // 视频动态露面就先把播放地址取回来，点开时通常已经有结果了。
                        if let video = entry.video,
                           video.canDisplayVideo(hidingPortrait: hidesPortraitVideos) {
                            await VideoPreparationCache.shared.prefetch(bvid: video.bvid)
                        }
                    }
            }

            if feed.isLoadingMore {
                LoadingTaskAnchor()
                    .padding()
            }
        }
    }

    private func updatePullFade(_ distance: CGFloat) {
        guard !isRefreshing, !reduceMotion else { return }
        let progress = Double(min(max(distance, 0) / CGFloat(HomeRefreshSettings.clamped(refreshDistance)), 1))
        refreshOpacity = 1 - FeedRefreshTuning.pullFade * progress
    }

    private func startRefresh() {
        guard !isRefreshing, !isSidebarExpanded else { return }
        refreshTask?.cancel()
        selectionTransitionTask?.cancel()
        pendingSelectionID = nil
        feedOpacity = 1
        isRefreshing = true
        landingWindow = false
        let model = viewModel
        let feed = model.activeFeed
        let duration = reduceMotion ? 0 : FeedRefreshTuning.fadeExit(speed: exitSpeed)
        let stagingID = UUID()
        let started = Date.now
        withAnimation(.easeOut(duration: 0.25)) { listPosition.scrollTo(edge: .top) }
        if !reduceMotion {
            withAnimation(.easeOut(duration: duration)) { refreshOpacity = 0 }
        }
        refreshTask = Task { @MainActor in
            await model.refresh(staged: true, stagingID: stagingID)
            let remaining = max(0, duration - Date.now.timeIntervalSince(started))
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            // 离页或切换 UP 后只完成原数据源的提交，不改新页面的动画状态。
            guard !Task.isCancelled else { feed.commitStagedRefresh(id: stagingID); return }
            landingWindow = !reduceMotion
            feed.commitStagedRefresh(id: stagingID)
            refreshOpacity = 1
            landingGeneration += 1
            isRefreshing = false
            if landingWindow {
                try? await Task.sleep(for: .seconds(FeedRefreshTuning.landingWindow(speed: enterSpeed)))
                guard !Task.isCancelled else { return }
                landingWindow = false
            }
            refreshTask = nil
        }
    }

    private func cancelRefreshAnimation() {
        refreshTask?.cancel()
        refreshTask = nil
        pendingSelectionID = nil
        isRefreshing = false
        landingWindow = false
        refreshOpacity = 1
    }

    private var loadingPlaceholder: some View {
        LoadingTaskAnchor()
    }

    private func card(for entry: DynamicEntry) -> some View {
        DynamicCard(
            entry: entry,
            isLiked: viewModel.activeFeed.isLiked(entry),
            likeCount: viewModel.activeFeed.likeCount(entry),
            onOpenVideo: { open(entry) },
            // 卡片头像和轮盘中央头像都可以进入 UP 主页。
            onOpenAuthor: {
                path.append(
                    FollowedUp(
                        mid: entry.authorMid,
                        uname: entry.authorName,
                        face: entry.authorFace,
                        hasUpdate: false
                    )
                )
            },
            onLike: { like(entry) },
            onOpenDetail: { detailEntry = entry },
            showsAuthor: viewModel.selectedUp == nil
        )
        .videoTransitionSource("following-dynamic-\(entry.id)", in: dynamicTransition)
        .contextMenu {
            if let video = entry.video,
               video.canDisplayVideo(hidingPortrait: hidesPortraitVideos) {
                WatchLaterMenuButton(aid: video.aid > 0 ? video.aid : nil, bvid: video.bvid)
            }
        }
    }

    private func settleSelection(_ id: FollowingSelection.ID, refresh: Bool = false) {
        guard let target = viewModel.carouselItems.first(where: { $0.id == id }) else { return }
        guard pendingSelectionID != id else { return }
        // 重新选回当前页面时也要取消上一目标的等待。
        if target.id == viewModel.selectedTarget.id {
            if pendingSelectionID != nil {
                selectionTransitionTask?.cancel()
                pendingSelectionID = nil
                feedOpacity = 1
            }
            return
        }
        cancelRefreshAnimation()
        selectionTransitionTask?.cancel()
        pendingSelectionID = id
        feedOpacity = 1
        let model = viewModel
        let targetFeed = model.feed(for: target)
        let stagingID = UUID()
        selectionTransitionTask = Task { @MainActor in
            // 加载期间保留旧页面及其高度，新数据只暂存，不提前替换卡片。
            if refresh || targetFeed.entries.isEmpty {
                await targetFeed.refresh(staged: true, stagingID: stagingID)
            }
            guard !Task.isCancelled else {
                targetFeed.commitStagedRefresh(id: stagingID)
                return
            }
            if !reduceMotion {
                withAnimation(.easeOut(duration: 0.07)) { feedOpacity = 0 }
                do {
                    try await Task.sleep(for: .milliseconds(70))
                } catch {
                    targetFeed.commitStagedRefresh(id: stagingID)
                    return
                }
            }
            guard !Task.isCancelled else {
                targetFeed.commitStagedRefresh(id: stagingID)
                return
            }
            // 同一帧提交目标、数据和落位状态，避免闪过空状态或半成品列表。
            targetFeed.commitStagedRefresh(id: stagingID)
            model.select(target)
            pendingSelectionID = nil
            listPosition.scrollTo(edge: .top)

            // 缓存命中和首次网络加载都在内容就绪后触发同一套卡片落位。
            // 不提前淡入整页，否则数据稍后到达时会直接出现而没有动效。
            landingWindow = !reduceMotion
            landingGeneration += 1
            feedOpacity = 1

            if landingWindow {
                do {
                    try await Task.sleep(for: .seconds(FeedRefreshTuning.landingWindow(speed: enterSpeed)))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                landingWindow = false
            }
            selectionTransitionTask = nil
        }
    }

    private func open(_ entry: DynamicEntry) {
        guard let video = entry.video else { return }
        // 动态流不带 cid，进详情页后再取，和搜索结果的路径一样。
        nowPlaying.open(
            VideoDetailRoute(
                bvid: video.bvid,
                cover: video.cover,
                title: video.title,
                artist: video.authorName
            ),
            from: video.bvid
        )
    }

    private func like(_ entry: DynamicEntry) {
        Task {
            if let message = await viewModel.activeFeed.toggleLike(entry, isLoggedIn: account.isLoggedIn) {
                feedback.show(message)
            }
        }
    }
}

/// 覆盖整个页面与上下安全区的连续底板，侧边保留等距凹口。
private struct FollowingPageEdgeShape: Shape {
    let side: FollowingSidebarSide
    var progress: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let middle = rect.minY + topInset + (rect.height - topInset - bottomInset) / 2
        let expansion = min(max(progress, 0), 1)
        let reach = min(FollowingSidebarContour.reach, max(0, rect.height - topInset - bottomInset) / 2)
        // 底板边缘直接使用屏幕坐标，顶端、凹口、底端不再分开拼接。
        func point(at y: CGFloat) -> CGPoint {
            let edge = FollowingSidebarContour.pageEdge(at: y)
            return CGPoint(x: rect.minX + edge.x * expansion,
                           y: middle + y + (edge.y - y) * expansion)
        }
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: point(at: -reach).x, y: rect.minY))
        // 每半点一个采样，保持固定拓扑，展开和收起时仍可连续插值。
        for index in 0...400 {
            path.addLine(to: point(at: -reach + 2 * reach * CGFloat(index) / 400))
        }
        path.addLine(to: CGPoint(x: point(at: reach).x, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        if side == .right {
            return path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1,
                                                 tx: rect.minX + rect.maxX, ty: 0))
        }
        return path
    }
}

#Preview {
    FollowingView()
        .environment(NowPlayingStore())
        .environment(AccountStore())
        .environment(ActionFeedback())
}
