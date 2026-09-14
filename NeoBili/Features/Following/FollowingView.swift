import SwiftUI

/// 「关注」Tab：动态流与可收起的侧边关注选择器。
struct FollowingView: View {
    var onOpenLiveRoom: (LiveRoom) -> Void = { _ in }
    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(AccountStore.self) private var account
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.videoTransitionNamespace) private var videoTransition
    @Environment(\.hidesPortraitVideos) private var hidesPortraitVideos
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var sidebarMotion = FollowingSidebarMotion()
    @State private var listPosition = ScrollPosition(edge: .top)
    @AppStorage(HomeRefreshSettings.storageKey) private var refreshDistance = HomeRefreshSettings.defaultDistance
    @AppStorage(AnimationSpeedSettings.exitSpeedKey) private var exitSpeed = AnimationSpeedSettings.defaultSpeed
    @AppStorage(AnimationSpeedSettings.enterSpeedKey) private var enterSpeed = AnimationSpeedSettings.defaultSpeed
    @AppStorage(CardAnimationSettings.masterKey) private var cardAnimationsEnabled = true
    @AppStorage(CardAnimationSettings.dynamicEnterKey) private var dynamicEnterEnabled = true
    @AppStorage(CardAnimationSettings.dynamicExitKey) private var dynamicExitEnabled = true
    @State private var isRefreshing = false
    @State private var refreshOpacity = 1.0
    @State private var landingGeneration = 0
    @State private var landingWindow = false
    @State private var refreshTask: Task<Void, Never>?
    @State private var feedOpacity = 1.0
    @State private var selectionTransitionTask: Task<Void, Never>?
    @State private var pendingSelectionID: FollowingSelection.ID?
    @State private var isFollowingVisible = false
    @State private var isAvatarMenuPresented = false
    @State private var liveRefreshGeneration = 0

    private struct LiveRefreshContext: Hashable {
        let isActive: Bool
        let accountID: Int?
        let isLoggedIn: Bool
        let generation: Int
    }

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
                    FollowingPageBackground(
                        motion: sidebarMotion,
                        side: sidebarSide,
                        topInset: geometry.safeAreaInsets.top,
                        bottomInset: geometry.safeAreaInsets.bottom
                    )
                    .frame(width: geometry.size.width,
                           height: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom)
                    .offset(y: -geometry.safeAreaInsets.top)
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
            isAvatarMenuPresented = false
            sidebarMotion.reset()
            focusedTargetID = .all
            feedOpacity = 1
            listPosition.scrollTo(edge: .top)
            viewModel = FollowingViewModel()
        }
        .resolvePortraitVideos(viewModel.activeFeed.entries.compactMap(\.video), batchID: landingGeneration, animationCategory: .dynamic) {
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

    private var animatesCardEntrance: Bool { cardAnimationsEnabled && dynamicEnterEnabled && !reduceMotion }
    private var animatesCardExit: Bool { cardAnimationsEnabled && dynamicExitEnabled && !reduceMotion }

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
                        enabled: !isSidebarExpanded || sidebarMotion.isDragging,
                        side: sidebarSide,
                        onMove: { translation in
                            sidebarMotion.drag(translation: translation)
                            if !isSidebarExpanded { isSidebarExpanded = true }
                        },
                        onEnd: { velocity in
                            isSidebarExpanded = sidebarMotion.endDrag(velocity: velocity, reduceMotion: reduceMotion)
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
            if pendingSelectionID != nil || (!animatesCardExit && isRefreshing) {
                LoadingTaskAnchor().controlSize(.small).padding(.top, 12)
            }
        }
        .accessibilityAction(named: "刷新关注动态") { startRefresh() }
        // 卡片保持原始排版，再按剩余屏宽等比缩小；视口补偿使上下边缘仍与安全区衔接。
        .modifier(FollowingFeedPresentation(motion: sidebarMotion, side: sidebarSide))
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
                onOpenLive: { up in
                    guard let room = viewModel.liveRoom(for: up) else {
                        feedback.show("这位 UP 主已结束直播")
                        return
                    }
                    onOpenLiveRoom(room)
                },
                onContextMenuChange: { presented in
                    isAvatarMenuPresented = presented
                    if presented {
                        selectionTransitionTask?.cancel()
                        selectionTransitionTask = nil
                        pendingSelectionID = nil
                        feedOpacity = 1
                    }
                },
                motion: sidebarMotion,
                onCloseSwipe: { translation in
                    sidebarMotion.drag(translation: translation)
                },
                onCloseSwipeEnd: { velocity in
                    isSidebarExpanded = sidebarMotion.endDrag(velocity: velocity, reduceMotion: reduceMotion)
                }
            )
        }
        .onAppear { isFollowingVisible = true }
        .onChange(of: viewModel.carouselItems) { _, _ in
            viewModel.reconcileCarouselSelection()
        }
        .task(id: LiveRefreshContext(isActive: isFollowingVisible && scenePhase == .active,
                                     accountID: account.accountID, isLoggedIn: account.isLoggedIn, generation: liveRefreshGeneration)) {
            guard isFollowingVisible, scenePhase == .active, account.isLoggedIn else { return }
            let directory = viewModel.liveDirectory
            while !Task.isCancelled {
                await directory.refresh(force: liveRefreshGeneration > 0)
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
        .task(id: isSidebarExpanded && !isAvatarMenuPresented ? focusedTargetID : nil) {
            guard isSidebarExpanded, !isAvatarMenuPresented else { return }
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
            guard !Task.isCancelled, isSidebarExpanded, !isAvatarMenuPresented, focusedTargetID == targetID else { return }
            settleSelection(targetID, refresh: true)
        }
        .onChange(of: isSidebarExpanded) { _, expanded in
            sidebarMotion.settle(expanded: expanded, reduceMotion: reduceMotion)
            if !expanded, isFollowingVisible {
                settleSelection(focusedTargetID)
            }
        }
        .onChange(of: sidebarSide) { _, _ in
            isSidebarExpanded = false
            sidebarMotion.reset()
        }
        .onChange(of: reduceMotion) { _, enabled in
            if enabled { sidebarMotion.settle(expanded: isSidebarExpanded, reduceMotion: true) }
        }
        .onChange(of: animatesCardExit) { _, enabled in
            if !enabled {
                refreshOpacity = 1
                feedOpacity = 1
            }
        }
        .onChange(of: animatesCardEntrance) { _, enabled in
            if !enabled { landingWindow = false }
        }
        .onDisappear {
            isFollowingVisible = false
            isAvatarMenuPresented = false
            sidebarMotion.reset()
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
                              landing: landingWindow, speed: enterSpeed, reduceMotion: reduceMotion, category: .dynamic) {
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
        guard !isRefreshing, animatesCardExit else { return }
        let progress = Double(min(max(distance, 0) / CGFloat(HomeRefreshSettings.clamped(refreshDistance)), 1))
        let faded = 1 - FeedRefreshTuning.pullFade * progress
        // 值没变就不写状态：写 @State 会让整页 body 重算。
        if refreshOpacity != faded { refreshOpacity = faded }
    }

    private func startRefresh() {
        guard !isRefreshing, !isSidebarExpanded else { return }
        liveRefreshGeneration += 1
        refreshTask?.cancel()
        selectionTransitionTask?.cancel()
        pendingSelectionID = nil
        feedOpacity = 1
        isRefreshing = true
        landingWindow = false
        let model = viewModel
        let feed = model.activeFeed
        let duration = animatesCardExit ? FeedRefreshTuning.fadeExit(speed: exitSpeed) : 0
        let stagingID = UUID()
        let started = Date.now
        withAnimation(.easeOut(duration: 0.25)) { listPosition.scrollTo(edge: .top) }
        if animatesCardExit {
            withAnimation(.easeOut(duration: duration)) { refreshOpacity = 0 }
        }
        refreshTask = Task { @MainActor in
            await model.refresh(staged: true, stagingID: stagingID)
            let remaining = max(0, duration - Date.now.timeIntervalSince(started))
            if remaining > 0 {
                try? await CardAnimationSettings.waitWhileEnabled(for: remaining, category: .dynamic, phase: .exit)
            }
            // 离页或切换 UP 后只完成原数据源的提交，不改新页面的动画状态。
            guard !Task.isCancelled else { feed.commitStagedRefresh(id: stagingID); return }
            landingWindow = animatesCardEntrance
            feed.commitStagedRefresh(id: stagingID)
            refreshOpacity = 1
            landingGeneration += 1
            isRefreshing = false
            if landingWindow {
                try? await CardAnimationSettings.waitWhileEnabled(for: FeedRefreshTuning.landingWindow(speed: enterSpeed),
                                                                 category: .dynamic, phase: .enter)
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
            if animatesCardExit {
                withAnimation(.easeOut(duration: 0.07)) { feedOpacity = 0 }
                do {
                    try await CardAnimationSettings.waitWhileEnabled(for: 0.07, category: .dynamic, phase: .exit)
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
            landingWindow = animatesCardEntrance
            landingGeneration += 1
            feedOpacity = 1

            if landingWindow {
                do {
                    try await CardAnimationSettings.waitWhileEnabled(for: FeedRefreshTuning.landingWindow(speed: enterSpeed),
                                                                    category: .dynamic, phase: .enter)
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

/// 独立观察展开进度，整份动态数据不参与逐帧背景重绘。
private struct FollowingPageBackground: View {
    let motion: FollowingSidebarMotion
    let side: FollowingSidebarSide
    let topInset: CGFloat
    let bottomInset: CGFloat

    var body: some View {
        FollowingPageEdgeShape(side: side, progress: motion.progress,
                               topInset: topInset, bottomInset: bottomInset)
            .fill(Color(uiColor: .systemBackground))
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
