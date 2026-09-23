import SwiftUI

/// 列表卡片需要用同一个命名空间登记自己是 zoom 转场的起点，
/// 而这个命名空间属于最外层，所以走环境传下去。
extension EnvironmentValues {
    @Entry var videoTransitionNamespace: Namespace.ID?
    /// 切换标签时页面内容的淡入进度。各页只把它用在内容上，标题栏和顶部模糊不参与：
    /// 系统模糊在祖先半透明时不渲染，整页淡入会让模糊等淡入结束才出现。
    @Entry var tabContentOpacity: Double = 1
}

struct RootView: View {
    @State private var nowPlaying = NowPlayingStore()
    @State private var account = AccountStore()
    @State private var feedback = ActionFeedback()
    @State private var themeIcon = ThemeIconController(endpoint: .uiKit)
    @AppStorage(HomeTitleBarSettings.storageKey) private var pinsHomeTitleBar = HomeTitleBarSettings.defaultValue
    @AppStorage(MainTabSettings.orderKey) private var tabOrder = MainTabSettings.stored(MainTabSettings.defaultOrder)
    @AppStorage(PlaybackWindowSettings.storageKey) private var miniPlayerEnabled = PlaybackWindowSettings.defaultValue
    @AppStorage(AppTheme.storageKey) private var themeID = AppTheme.defaultID
    @State private var search = SearchViewModel()
    @State private var isSearchFocused = false
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var videoTransition

    /// 设置页那根滑杆选的档位。写在根视图上，改完立刻全 App 生效。
    @AppStorage(AppTextSize.storageKey) private var textSizeIndex = AppTextSize.defaultIndex
    /// 内容过滤同样在根视图转成环境值，所有列表即时响应设置变化。
    @AppStorage(PortraitVideoFilterSettings.storageKey) private var hidesPortraitVideos = PortraitVideoFilterSettings.defaultValue

    /// 主页面切换特效：新页面内容淡入，快慢用设置页那条「进入」滑杆。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AnimationSpeedSettings.enterSpeedKey) private var enterSpeed = AnimationSpeedSettings.defaultSpeed
    @AppStorage(CardAnimationSettings.masterKey) private var cardAnimationsEnabled = CardAnimationSettings.defaultValue
    @AppStorage(CardAnimationSettings.pageEnterKey) private var pageEntranceEnabled = CardAnimationSettings.defaultValue
    /// 当前页面。点下去立刻就换，高亮跟着立刻走。
    @State private var displayedTab = MainTabSettings.launchTab(
        from: UserDefaults.standard.string(forKey: MainTabSettings.launchKey) ?? ""
    )
    /// 新页面的浓度：切换那一刻置 0，随后淡入。
    @State private var tabContentOpacity: Double = 1
    @State private var tabSwitchTask: Task<Void, Never>?

    var body: some View {
        @Bindable var nowPlaying = nowPlaying

        return TabView(selection: tabSelection) {
            // 顺序来自设置；各页以自身为 id，调整顺序不会重建页面和丢失状态。
            ForEach(MainTabSettings.order(from: tabOrder)) { tab in
                Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                    page(for: tab)
                }
            }
            Tab(MainTab.search.title, systemImage: MainTab.search.systemImage, value: MainTab.search, role: .search) {
                NavigationStack {
                    SearchPage(viewModel: search, isFocused: $isSearchFocused, onSubmit: submitSearch)
                }
                .tint(.primary)
                .background {
                    Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                }
            }
        }
        .background {
            TabReselectionObserver {
                guard !nowPlaying.isExpanded, !nowPlaying.isServiceSheetPresented else { return }
                if displayedTab == .search { isSearchFocused = true }
                if displayedTab == .home { NotificationCenter.default.post(name: .homeTabReselected, object: nil) }
                if displayedTab == .live { NotificationCenter.default.post(name: .liveTabReselected, object: nil) }
                if displayedTab == .following { NotificationCenter.default.post(name: .followingTabReselected, object: nil) }
            }.frame(width: 0, height: 0)
        }
        .tint(AppTheme.selected(themeID).color)
        .tabBarMinimizeBehavior(miniPlayerEnabled ? .onScrollDown : .never)
        .onChange(of: miniPlayerEnabled) { nowPlaying.applyMiniPlayerSetting() }
        .tabMiniPlayerHost(isActive: { !nowPlaying.isServiceSheetPresented }, transitionNamespace: videoTransition)
        .task(id: search.trimmedQuery) { await search.loadSuggestions() }
        .onChange(of: search.trimmedQuery) {
            if search.trimmedQuery.isEmpty { search.reset() }
        }
        // 提示浮层只包住 TabView，不要包住下面那个 fullScreenCover。
        //
        // 浮层内部带一个 `.animation(value:)`，把它套在 cover 外面时，每次提示
        // 出现/消失都会给整条链路（含 cover 和它的 zoom 转场）开一次动画事务，
        // 视频页重新 present 时会因此被构建两遍，出现两个渲染容器互相抢渲染层。
        .actionFeedbackOverlay()
        // 视频页由最外层持有，播放器和整页状态统一由 NowPlayingStore 管理；
        // 视频页退出后由 store 将播放器交给小窗，关闭小窗时才释放。
        .fullScreenCover(item: Binding(
            get: { nowPlaying.isServiceSheetPresented ? nil : nowPlaying.videoPresentation },
            set: { destination in
                guard !nowPlaying.isServiceSheetPresented else { return }
                if destination != nil { nowPlaying.isExpanded = true }
                else { nowPlaying.dismissVideoPage() }
            }
        ), onDismiss: nowPlaying.finishDismissal) { _ in
            Group {
                if let player = nowPlaying.livePlayer {
                    LiveRoomView(player: player, keepsPlaybackOnDismiss: true,
                                 onReturn: nowPlaying.dismissVideoPage)
                } else {
                    VideoPage()
                }
            }
                .appTextSize()
                .presentationBackground(.clear)
                .presentationContentInteraction(.resizes)
                .navigationTransition(.zoom(sourceID: MediaPresentationState.Source.player,
                                            in: videoTransition))
                .background { VideoPagePresentationObserver(
                    onDidAppear: nowPlaying.videoPageDidAppear,
                    onInteractionBegan: nowPlaying.videoPageInteractionBegan,
                    onInteractionEnded: nowPlaying.videoPageInteractionEnded
                ) }
        }
        // 底部内容直接延伸，不加系统渐变模糊。
        #if PERFORMANCE_DEMO
        .overlay(alignment: .topTrailing) { PerformanceDemoControl(store: nowPlaying) }
        #endif
        .scrollEdgeEffectHidden(true, for: .bottom)
        .appTheme()
        .environment(nowPlaying)
        .environment(account)
        .environment(feedback)
        .environment(themeIcon)
        .environment(\.videoTransitionNamespace, videoTransition)
        .environment(\.tabContentOpacity, tabContentOpacity)
        .environment(\.hidesPortraitVideos, hidesPortraitVideos)
        // 全 App 的文字大小由设置页那根滑杆决定，不跟随系统的动态字体——
        // 两套缩放同时生效的话，同一个界面在不同设备上会被叠加缩放两次。
        // 在这里注入等于把系统档位整个覆盖掉。
        .dynamicTypeSize(AppTextSize.size(at: textSizeIndex))
        // 冷启动时用 Keychain 里可能存在的登录凭据恢复会话；
        // 「我的」页在恢复完成前不会闪出登录按钮。
        .task { await account.restoreSessionIfNeeded() }
        .task(id: "\(themeID)-\(scenePhase == .active)") {
            guard scenePhase == .active else { return }
            // Coalesce rapid taps before asking the system to change the icon.
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            await themeIcon.apply(themeID: themeID)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await account.retrySessionIfNeeded() } }
            else { nowPlaying.player?.savePlaybackProgress() }
        }
        .onChange(of: animatesPageEntrance) { _, enabled in
            if !enabled { finishTabEntrance() }
        }
        .onChange(of: account.sessionID) { nowPlaying.close() }
    }

    @ViewBuilder
    private func page(for tab: MainTab) -> some View {
        switch tab {
        case .live:
            LiveView(onOpenRoom: openLiveRoom)
                .tint(.primary)
        case .home:
            // 标题栏的两套实现由设置切换，各自持有列表和数据。
            Group {
                if pinsHomeTitleBar { HomePinnedHomeView() } else { HomeView() }
            }
            .tint(.primary)
        case .following:
            FollowingView(onOpenLiveRoom: { openLiveRoom($0, sourceID: "following-live") })
                .id(account.sessionID)
                .tint(.primary)
        case .search:
            EmptyView()
        }
    }

    private func submitSearch(_ keyword: String?) {
        search.submit(keyword: keyword)
        guard search.hasSubmittedSearch else { return }
        // 提交后保留顶部搜索框，只收起键盘。
        isSearchFocused = false
    }

    private func openLiveRoom(_ room: LiveRoom, sourceID: String) {
        nowPlaying.openLive(room, from: sourceID)
    }

    /// TabView 的 selection 走这个代理：内容和高亮照常立刻切换，
    /// 只给新页面补一段淡入。
    ///
    /// 旧页面没有淡出——TabView 的内容按选中项懒建，切换那一刻它已经不在视图树里了。
    /// 要让它淡出就得推迟切换，而推迟多久高亮就滞后多久，点起来不跟手。
    private var tabSelection: Binding<MainTab> {
        Binding(
            get: { displayedTab },
            set: { switchTab(to: $0) }
        )
    }

    private func switchTab(to tab: MainTab) {
        // 重复点当前 Tab 是"回到顶部/刷新"的手势，
        // 由 TabReselectionObserver 单独接管，这里不插手。
        guard tab != displayedTab else { return }

        tabSwitchTask?.cancel()

        // 新页面的内容淡入；搜索页保持输入框立即可用，不参与。
        isSearchFocused = false
        guard animatesPageEntrance, tab != .search else {
            finishTabEntrance()
            displayedTab = tab
            return
        }

        tabContentOpacity = 0
        displayedTab = tab

        let fadeIn = AnimationSpeedSettings.tabFade(speed: enterSpeed)
        tabSwitchTask = Task { @MainActor in
            // 隔一帧再启动：同一帧内改两次状态会被合并成"没有动画"。
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: fadeIn)) { tabContentOpacity = 1 }
        }
    }

    private var animatesPageEntrance: Bool {
        !reduceMotion && cardAnimationsEnabled && pageEntranceEnabled
    }

    private func finishTabEntrance() {
        tabSwitchTask?.cancel()
        tabSwitchTask = nil
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { tabContentOpacity = 1 }
    }
}

#Preview {
    RootView()
}
