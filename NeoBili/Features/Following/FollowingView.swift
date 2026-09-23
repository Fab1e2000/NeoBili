import SwiftUI

/// 「关注」Tab：动态流与可收起的侧边关注选择器。
struct FollowingView: View {
    var onOpenLiveRoom: (LiveRoom) -> Void = { _ in }

    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(AccountStore.self) private var account
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.videoTransitionNamespace) private var videoTransition
    @Environment(\.tabContentOpacity) private var tabContentOpacity
    @Environment(\.hidesPortraitVideos) private var hidesPortraitVideos
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var dynamicTransition

    // 设置
    @AppStorage(FollowingSidebarSide.storageKey) private var sidebarSide: FollowingSidebarSide = .left
    @AppStorage(FollowingSidebarDwellSettings.storageKey) private var sidebarDwellDuration = FollowingSidebarDwellSettings.defaultDuration
    @AppStorage(HomeRefreshSettings.storageKey) private var refreshDistance = HomeRefreshSettings.defaultDistance
    @AppStorage(AnimationSpeedSettings.exitSpeedKey) private var exitSpeed = AnimationSpeedSettings.defaultSpeed
    @AppStorage(AnimationSpeedSettings.enterSpeedKey) private var enterSpeed = AnimationSpeedSettings.defaultSpeed
    @AppStorage(CardAnimationSettings.masterKey) private var cardAnimationsEnabled = CardAnimationSettings.defaultValue
    @AppStorage(CardAnimationSettings.dynamicExitKey) private var dynamicExitEnabled = CardAnimationSettings.defaultValue
    @AppStorage(CardAnimationSettings.dynamicRefreshEnterKey) private var dynamicEnterEnabled = CardAnimationSettings.defaultValue

    // 数据与导航
    @State private var viewModel = FollowingViewModel()
    @State private var path: [FollowedUp] = []
    /// 正在看哪条动态的详情。有值时推入详情页。
    @State private var detailEntry: DynamicEntry?
    @State private var isFollowingVisible = false
    @State private var liveRefreshGeneration = 0

    // 侧边选择器
    /// 轮盘拖动时的视觉焦点；只有停稳后才提交给 ViewModel。
    @State private var focusedTargetID: FollowingSelection.ID = .all
    @State private var isSidebarExpanded = false
    @State private var sidebarMotion = FollowingSidebarMotion()
    @State private var isAvatarMenuPresented = false
    @State private var selectionTransitionTask: Task<Void, Never>?
    @State private var pendingSelectionID: FollowingSelection.ID?

    // 列表滚动与刷新
    @State private var listPosition = ScrollPosition(edge: .top)
    @State private var isAwayFromTop = false
    @State private var shortcutTask: Task<Void, Never>?
    @State private var isRefreshing = false
    @State private var refreshTask: Task<Void, Never>?
    @State private var refreshOpacity = 1.0
    @State private var feedOpacity = 1.0
    @State private var feedGeneration = 0

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
                // 列表缩小后自带的顶部渐变只覆盖列表宽度，展开选择器时补一层全宽的顶部模糊。
                .overlay(alignment: .top) {
                    FollowingExpandedTopBlur(motion: sidebarMotion, topInset: geometry.safeAreaInsets.top)
                }
            }
            // 页头固定在顶部，不随动态滚动、也不随侧栏缩放，层级在选择器和动态之上。
            // 作为顶部栏挂在外层，上面的 geometry 安全区因此包含页头，模糊和底板随之让位。
            .safeAreaBar(edge: .top, spacing: 0) { header }
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
        .resolvePortraitVideos(viewModel.activeFeed.entries.compactMap(\.video), batchID: feedGeneration, animationCategory: .dynamic) {
            let feed = viewModel.activeFeed
            await feed.loadReplacementPage()
            return feed.entries.compactMap(\.video)
        }
    }

    private var loggedOutView: some View {
        ContentUnavailableView {
            Label("尚未登录", systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            Text("登录后这里会显示你关注的 UP 主的最新动态。\n点右上角头像即可登录。")
        }
    }

    private var header: some View {
        PageHeader(title: "关注", transitionID: "mine-avatar-following")
            .padding(.horizontal, 20)
    }

    // MARK: - 已登录

    private var feed: some View {
        list
            .task(id: account.accountID) {
                FollowingReadStore.shared.configure(accountID: account.accountID)
                await viewModel.loadInitial()
            }

    }

    private var animatesCardExit: Bool { cardAnimationsEnabled && dynamicExitEnabled && !reduceMotion }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                feedContent
            }
            // 切换标签只淡入动态；列表本身保持不透明，顶部模糊立即出现。
            .opacity(feedOpacity * refreshOpacity * tabContentOpacity)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            // 手势观察器不参与纵向布局，避免独立零高占位产生默认间距。
            .background(alignment: .top) {
                ShortPullRefresh(
                    threshold: refreshDistance,
                    enabled: !isRefreshing && !isSidebarExpanded,
                    onProgress: { _, _ in },
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
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 1 } action: { _, away in
            isAwayFromTop = away
        }
        // 即使内容不足一屏也允许下拉刷新。
        .scrollBounceBehavior(.always, axes: .vertical)
        // 与直播页一致：页头下缘是清晰的切边，而不是渐隐。
        .scrollEdgeEffectStyle(.hard, for: .top)
            .scrollEdgeEffectHidden(true, for: .bottom)
        .scrollDisabled((isRefreshing && refreshOpacity < 1) || pendingSelectionID != nil)
        // 下拉刷新与推荐页一致，不显示提示框；只在切换 UP 主等待数据时给个小菊花。
        .overlay(alignment: .top) {
            if pendingSelectionID != nil {
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
            // 每次回到关注页立即请求，不受上次成功后 60 秒缓存窗口限制。
            await directory.refresh(force: true)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                await directory.refresh()
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
        // 与推荐页一致：重复点「关注」标签，不在顶部时回到顶部，已在顶部时刷新。
        .onTabReselected(.following) {
            guard account.isLoggedIn, shortcutTask == nil, !isRefreshing, !isSidebarExpanded,
                  path.isEmpty, detailEntry == nil else { return }
            if isAwayFromTop {
                withAnimation(reduceMotion ? nil : .smooth) { listPosition.scrollTo(edge: .top) }
                // 回顶动画结束前忽略重复点击，避免误触发刷新。
                shortcutTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    shortcutTask = nil
                }
            } else {
                startRefresh()
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
            ForEach(visibleEntries) { entry in
                card(for: entry, lastVisibleID: visibleEntries.last?.id)
                    .videoEntranceIdentity(entry.video?.bvid)
                    .padding(.horizontal, DynamicCardLayout.pageHorizontalInset)
                    .padding(.vertical, DynamicCardLayout.cardVerticalSpacing)
            }

            if feed.isLoadingMore {
                LoadingTaskAnchor()
                    .padding()
            }
        }
    }

    private func startRefresh() {
        guard !isRefreshing, !isSidebarExpanded else { return }
        liveRefreshGeneration += 1
        refreshTask?.cancel()
        selectionTransitionTask?.cancel()
        pendingSelectionID = nil
        feedOpacity = 1
        isRefreshing = true
        let model = viewModel
        let feed = model.activeFeed
        let duration = animatesCardExit ? FeedRefreshTuning.fadeExit(speed: exitSpeed) : 0
        let stagingID = UUID()
        // 与推荐页一致：松手即开始淡出，请求并行进行，两者都结束后再换上新内容。
        let exitStart = ProcessInfo.processInfo.systemUptime
        refreshOpacity = 1
        if duration > 0 { withAnimation(.easeOut(duration: duration)) { refreshOpacity = 0 } }

        refreshTask = Task { @MainActor in
            await model.refresh(staged: true, stagingID: stagingID)
            guard !Task.isCancelled else { feed.commitStagedRefresh(id: stagingID); return }
            guard feed.errorMessage == nil else {
                // 刷新失败保留旧内容，直接恢复显示，不弹提示。
                withAnimation(nil) { refreshOpacity = 1 }
                isRefreshing = false
                refreshTask = nil
                return
            }
            if duration > 0 {
                let remaining = max(0, duration - (ProcessInfo.processInfo.systemUptime - exitStart))
                try? await CardAnimationSettings.waitWhileEnabled(for: remaining, category: .dynamic, phase: .exit)
            }
            // 离页或切换 UP 后只完成原数据源的提交，不改新页面的动画状态。
            guard !Task.isCancelled else { feed.commitStagedRefresh(id: stagingID); return }
            // 与推荐页一致：新内容换上后淡入。刷新回来的动态常与原来相同，
            // 卡片自带的入场不会重播，所以由整列来淡入。
            let animatesEnter = cardAnimationsEnabled && dynamicEnterEnabled && !reduceMotion
            withAnimation(nil) {
                feed.commitStagedRefresh(id: stagingID)
                refreshOpacity = animatesEnter ? 0 : 1
                feedGeneration += 1
                isRefreshing = false
            }
            if animatesEnter {
                // 隔一帧再启动：同一帧内先置 0 再改回 1 会被合并成没有动画。
                try? await Task.sleep(for: .milliseconds(16))
                // 期间又开始了新的刷新时由新刷新接管浓度。
                if !Task.isCancelled {
                    withAnimation(.easeIn(duration: FeedRefreshTuning.fadeInDuration / AnimationSpeedSettings.clamped(enterSpeed))) {
                        refreshOpacity = 1
                    }
                }
            }
            refreshTask = nil
        }
    }

    private func cancelRefreshAnimation() {
        refreshTask?.cancel()
        refreshTask = nil
        pendingSelectionID = nil
        isRefreshing = false
        refreshOpacity = 1
    }

    private var loadingPlaceholder: some View {
        LoadingTaskAnchor()
    }

    private func card(for entry: DynamicEntry, lastVisibleID: String?) -> some View {
        DynamicFeedCard(
            entry: entry,
            feed: viewModel.activeFeed,
            lastVisibleID: lastVisibleID,
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
            // 同一帧提交目标和数据，避免闪过空状态或半成品列表。
            targetFeed.commitStagedRefresh(id: stagingID)
            model.select(target)
            pendingSelectionID = nil
            listPosition.scrollTo(edge: .top)

            // 更新过滤批次；新卡片直接显示，不再等待进入动画。
            feedGeneration += 1
            feedOpacity = 1

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

/// 选择器展开时的全宽顶部模糊，浓度跟随展开进度；下缘与页头对齐成切边。
/// 单独一个视图读取逐帧的进度，拖动时不会让整个关注页重算。
private struct FollowingExpandedTopBlur: View {
    let motion: FollowingSidebarMotion
    let topInset: CGFloat

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .frame(height: topInset)
            .offset(y: -topInset)
            .opacity(motion.progress)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
