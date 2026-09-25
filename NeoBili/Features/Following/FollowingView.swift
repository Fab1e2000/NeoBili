import SwiftUI

/// 关注页的推入目标：UP 主空间，或「全部关注」列表。
enum FollowingRoute: Hashable {
    case space(FollowedUp)
    case allFollowings
}

/// 「关注」Tab：标题下方是横向头像条，下面是动态流。
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
    @AppStorage(TitleBarSettings.storageKey) private var pinsTitleBar = TitleBarSettings.defaultValue
    @AppStorage(HomeRefreshSettings.storageKey) private var refreshDistance = HomeRefreshSettings.defaultDistance
    @AppStorage(AnimationSpeedSettings.exitSpeedKey) private var exitSpeed = AnimationSpeedSettings.defaultExitSpeed
    @AppStorage(AnimationSpeedSettings.enterSpeedKey) private var enterSpeed = AnimationSpeedSettings.defaultEnterSpeed
    @AppStorage(CardAnimationSettings.masterKey) private var cardAnimationsEnabled = CardAnimationSettings.defaultValue
    @AppStorage(CardAnimationSettings.dynamicExitKey) private var dynamicExitEnabled = CardAnimationSettings.defaultValue
    @AppStorage(CardAnimationSettings.dynamicRefreshEnterKey) private var dynamicEnterEnabled = CardAnimationSettings.defaultValue

    // 数据与导航
    @State private var viewModel = FollowingViewModel()
    @State private var path: [FollowingRoute] = []
    /// 正在看哪条动态的详情。有值时推入详情页。
    @State private var detailEntry: DynamicEntry?
    @State private var isFollowingVisible = false
    @State private var liveRefreshGeneration = 0

    // 头像条切换
    @State private var selectionTransitionTask: Task<Void, Never>?
    /// 已点选、正在淡出旧动态或等待数据的目标；头像条立即高亮它。
    @State private var pendingSelectionID: FollowingSelection.ID?
    /// 目标动态需要联网加载时才显示小菊花，缓存命中的切换不闪提示。
    @State private var isSelectionLoading = false

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
            .background(Color(uiColor: .systemGroupedBackground))
            // 固定标题栏：与直播页一样，标题和头像条一起常驻顶部栏，动态从下面滑过。
            // 随内容滚动：两者是动态列表的第一行（见 `list`）。未登录时没有列表，页头仍放在顶部栏。
            .safeAreaBar(edge: .top, spacing: 0) {
                if pinsTitleBar || !account.isLoggedIn { headerBlock }
            }
            .navigationTitle("关注")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: FollowingRoute.self) { route in
                switch route {
                case .space(let up):
                    SpaceView(up: up)
                case .allFollowings:
                    FollowingAllUpsView(
                        mid: account.accountID ?? 0,
                        decorated: Dictionary(viewModel.selectionItems.compactMap(\.up).map { ($0.mid, $0) },
                                              uniquingKeysWith: { first, _ in first }),
                        onOpenUp: { path.append(.space($0)) }
                    )
                }
            }
            .fullScreenCover(item: $detailEntry) { entry in
                NavigationStack {
                    DynamicDetailView(entry: entry, feed: viewModel.activeFeed)
                }
                .appTextSize()
                .actionFeedbackOverlay()
                .navigationTransition(.zoom(sourceID: "following-dynamic-\(entry.id)", in: dynamicTransition))
            }
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
            pendingSelectionID = nil
            isSelectionLoading = false
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
            Text(String(localized: "登录后这里会显示你关注的 UP 主的最新动态。\n点右上角头像即可登录。"))
        }
    }

    /// 标题与头像条是一个整体：固定时一起常驻顶部，随内容滚动时一起滚走。
    private var headerBlock: some View {
        VStack(spacing: 0) {
            PageHeader(title: String(localized: "关注"))
                .padding(.horizontal, 20)
            if account.isLoggedIn {
                FollowingUpStrip(
                    items: viewModel.selectionItems,
                    selectedID: pendingSelectionID ?? viewModel.selectedTarget.id,
                    onSelect: select,
                    onOpenUp: { path.append(.space($0)) },
                    onOpenLive: { up in
                        guard let room = viewModel.liveRoom(for: up) else {
                            feedback.show(String(localized: "这位 UP 主已结束直播"))
                            return
                        }
                        onOpenLiveRoom(room)
                    },
                    onOpenAll: { path.append(.allFollowings) }
                )
            }
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

    private var animatesCardExit: Bool { cardAnimationsEnabled && dynamicExitEnabled && !reduceMotion }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !pinsTitleBar { headerBlock.staysInPlaceWhenPulled() }
                LazyVStack(spacing: 0) {
                    feedContent
                }
                // 切换 UP 主与刷新都只淡动态；列表本身保持不透明，顶部模糊立即出现。
                .opacity(feedOpacity * refreshOpacity * tabContentOpacity)
                .overlay(alignment: .top) {
                    if isSelectionLoading {
                        LoadingTaskAnchor().controlSize(.small).padding(.top, 24)
                    }
                }
                // 手势观察器不参与纵向布局，避免独立零高占位产生默认间距。
                .background(alignment: .top) {
                    ShortPullRefresh(
                        threshold: refreshDistance,
                        enabled: !isRefreshing,
                        onProgress: { _, _ in },
                        onRefresh: startRefresh
                    )
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
        }
        .scrollPosition($listPosition)
        .tracksPageHeaderPull()
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 1 } action: { _, away in
            isAwayFromTop = away
        }
        // 即使内容不足一屏也允许下拉刷新。
        .scrollBounceBehavior(.always, axes: .vertical)
        .scrollEdgeEffectHidden(true, for: .bottom)
        .scrollDisabled(isRefreshing && refreshOpacity < 1)
        .accessibilityAction(named: "刷新关注动态") { startRefresh() }
        // 左缘一小条是触控死区：点击不生效，避免滑动返回时误触卡片。
        .leftEdgeTapDeadZone()
        .onAppear { isFollowingVisible = true }
        .onChange(of: viewModel.selectionItems) { _, _ in
            viewModel.reconcileSelection()
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
        // 与推荐页一致：重复点「关注」标签，不在顶部时回到顶部，已在顶部时刷新。
        .onTabReselected(.following) {
            guard account.isLoggedIn, shortcutTask == nil, !isRefreshing,
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
        .onChange(of: animatesCardExit) { _, enabled in
            if !enabled {
                refreshOpacity = 1
                feedOpacity = 1
            }
        }
        .onDisappear {
            isFollowingVisible = false
            cancelRefreshAnimation()
            cancelSelectionTransition()
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
        guard !isRefreshing else { return }
        liveRefreshGeneration += 1
        refreshTask?.cancel()
        cancelSelectionTransition()
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
            // 卡片头像和头像条的长按菜单都可以进入 UP 主页。
            onOpenAuthor: {
                path.append(.space(
                    FollowedUp(
                        mid: entry.authorMid,
                        uname: entry.authorName,
                        face: entry.authorFace,
                        hasUpdate: false
                    )
                ))
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

    private var animatesCardEnter: Bool { cardAnimationsEnabled && dynamicEnterEnabled && !reduceMotion }

    /// 轻点头像立即切换：旧动态淡出的同时取数据，两者都结束后换上新动态再淡入。
    private func select(_ target: FollowingSelection) {
        // 点回当前页面：取消尚未完成的切换，把淡出的动态恢复出来。
        if target.id == viewModel.selectedTarget.id {
            guard pendingSelectionID != nil else { return }
            selectionTransitionTask?.cancel()
            selectionTransitionTask = nil
            pendingSelectionID = nil
            isSelectionLoading = false
            withAnimation(animatesCardEnter ? .easeIn(duration: fadeInDuration) : nil) { feedOpacity = 1 }
            return
        }
        guard pendingSelectionID != target.id else { return }
        cancelRefreshAnimation()
        selectionTransitionTask?.cancel()
        pendingSelectionID = target.id
        let model = viewModel
        let targetFeed = model.feed(for: target)
        // 有更新的 UP 主总是重新拉取：既拿到新动态，也让服务端清除他的红点。
        let hadUpdate = model.beginSelection(target)
        let needsLoad = targetFeed.entries.isEmpty || hadUpdate
        let stagingID = UUID()
        let exitDuration = animatesCardExit ? FollowingSwitchFade.exit / AnimationSpeedSettings.clamped(exitSpeed) : 0
        let exitStart = ProcessInfo.processInfo.systemUptime
        if exitDuration > 0 { withAnimation(.easeOut(duration: exitDuration)) { feedOpacity = 0 } }

        selectionTransitionTask = Task { @MainActor in
            // 加载期间保留旧页面及其高度，新数据只暂存，不提前替换卡片。
            if needsLoad {
                isSelectionLoading = true
                await targetFeed.refresh(staged: true, stagingID: stagingID)
                // 被下一次点选取消时，菊花归新的切换管。
                if !Task.isCancelled { isSelectionLoading = false }
            }
            guard !Task.isCancelled else { targetFeed.commitStagedRefresh(id: stagingID); return }
            if exitDuration > 0 {
                let remaining = max(0, exitDuration - (ProcessInfo.processInfo.systemUptime - exitStart))
                do {
                    try await CardAnimationSettings.waitWhileEnabled(for: remaining, category: .dynamic, phase: .exit)
                } catch {
                    targetFeed.commitStagedRefresh(id: stagingID)
                    return
                }
            }
            guard !Task.isCancelled else { targetFeed.commitStagedRefresh(id: stagingID); return }
            // 同一帧提交目标和数据，避免闪过空状态或半成品列表。
            let animatesEnter = animatesCardEnter
            withAnimation(nil) {
                targetFeed.commitStagedRefresh(id: stagingID)
                model.select(target)
                pendingSelectionID = nil
                listPosition.scrollTo(edge: .top)
                feedGeneration += 1
                feedOpacity = animatesEnter ? 0 : 1
            }
            if animatesEnter {
                // 隔一帧再启动：同一帧内先置 0 再改回 1 会被合并成没有动画。
                try? await Task.sleep(for: .milliseconds(16))
                if !Task.isCancelled {
                    withAnimation(.easeIn(duration: fadeInDuration)) { feedOpacity = 1 }
                }
            }
            selectionTransitionTask = nil
        }
    }

    private var fadeInDuration: Double {
        FeedRefreshTuning.fadeInDuration / AnimationSpeedSettings.clamped(enterSpeed)
    }

    private func cancelSelectionTransition() {
        selectionTransitionTask?.cancel()
        selectionTransitionTask = nil
        pendingSelectionID = nil
        isSelectionLoading = false
        feedOpacity = 1
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

/// 切换 UP 主时旧动态的淡出时长。比下拉刷新的淡出短得多：轻点是明确的操作，应当立刻有回应。
private enum FollowingSwitchFade {
    static let exit: Double = 0.15
}

#Preview {
    FollowingView()
        .environment(NowPlayingStore())
        .environment(AccountStore())
        .environment(ActionFeedback())
}
