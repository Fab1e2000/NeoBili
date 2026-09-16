import SwiftUI

/// 列表卡片需要用同一个命名空间登记自己是 zoom 转场的起点，
/// 而这个命名空间属于最外层，所以走环境传下去。
extension EnvironmentValues {
    @Entry var videoTransitionNamespace: Namespace.ID?
}

extension View {
    /// 把这个视图登记成 zoom 转场的起点。命名空间还没准备好时原样返回。
    @ViewBuilder
    func videoTransitionSource(_ id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            matchedTransitionSource(id: id, in: namespace)
                .background { MediaZoomSource(id: id, namespace: namespace) }
        } else {
            self
        }
    }
}

/// 主页面保持独立导航与数据状态。
enum MainTab: Hashable {
    case home, following, live, mine, search
}

struct RootView: View {
    @State private var nowPlaying = NowPlayingStore()
    @State private var account = AccountStore()
    @State private var feedback = ActionFeedback()
    @State private var themeIcon = ThemeIconController()
    @AppStorage(AppTheme.storageKey) private var themeID = AppTheme.defaultID
    @State private var search = SearchViewModel()
    @State private var isSearchPresented = false
    @FocusState private var isSearchFocused: Bool
    @State private var searchReturnTab: MainTab = .home
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var videoTransition

    /// 设置页那根滑杆选的档位。写在根视图上，改完立刻全 App 生效。
    @AppStorage(AppTextSize.storageKey) private var textSizeIndex = AppTextSize.defaultIndex
    /// 内容过滤同样在根视图转成环境值，所有列表即时响应设置变化。
    @AppStorage(PortraitVideoFilterSettings.storageKey) private var hidesPortraitVideos = PortraitVideoFilterSettings.defaultValue

    /// 主页面切换特效：新页面淡入，快慢用设置页那条「进入」滑杆。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AnimationSpeedSettings.enterSpeedKey) private var enterSpeed = AnimationSpeedSettings.defaultSpeed
    @AppStorage(CardAnimationSettings.masterKey) private var cardAnimationsEnabled = CardAnimationSettings.defaultValue
    @AppStorage(CardAnimationSettings.pageEnterKey) private var pageEntranceEnabled = CardAnimationSettings.defaultValue
    /// 当前页面。点下去立刻就换，高亮跟着立刻走。
    @State private var displayedTab: MainTab = .home
    /// 新页面的浓度：切换那一刻置 0，随后淡入。
    @State private var tabContentOpacity: Double = 1
    @State private var tabSwitchTask: Task<Void, Never>?

    var body: some View {
        @Bindable var nowPlaying = nowPlaying

        return TabView(selection: tabSelection) {
            Tab("直播", systemImage: "dot.radiowaves.left.and.right", value: MainTab.live) {
                LiveView(onOpenRoom: openLiveRoom)
                .opacity(tabContentOpacity)
            }
            Tab("推荐", systemImage: "house.fill", value: MainTab.home) {
                HomeView().opacity(tabContentOpacity)
            }
            Tab("关注", systemImage: "person.2.fill", value: MainTab.following) {
                FollowingView(onOpenLiveRoom: { openLiveRoom($0, sourceID: "following-live") }).id(account.sessionID).opacity(tabContentOpacity)
            }
            Tab("我的", systemImage: "person.crop.circle", value: MainTab.mine) {
                MineView().opacity(tabContentOpacity)
            }
            Tab("搜索", systemImage: "magnifyingglass", value: MainTab.search, role: .search) {
                NavigationStack {
                    SearchPage(viewModel: search, onSubmit: submitSearch)
                }
                // 搜索仅属于这一条导航栈，退出时不会迁移到其它 Tab 的顶部。
                .searchable(text: $search.query, isPresented: $isSearchPresented, prompt: "搜索视频")
                .searchFocused($isSearchFocused)
                .onSubmit(of: .search) { submitSearch(nil) }
                .background {
                    Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabMiniPlayerHost(isActive: { !nowPlaying.isServiceSheetPresented }, transitionNamespace: videoTransition)
        .tabViewSearchActivation(.searchTabSelection)
        .onChange(of: isSearchPresented) { wasPresented, presented in
            // 取消搜索一次返回原页面；失去键盘焦点本身不结束搜索。
            guard wasPresented, !presented, displayedTab == .search,
                  !nowPlaying.isExpanded, !nowPlaying.isServiceSheetPresented else { return }
            switchTab(to: searchReturnTab)
        }
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
        .mediaZoomCover(isPresented: Binding(
            get: { nowPlaying.isExpanded && !nowPlaying.isServiceSheetPresented },
            set: {
                guard !nowPlaying.isServiceSheetPresented else { return }
                if $0 { nowPlaying.isExpanded = true } else { nowPlaying.dismissVideoPage() }
            }
        ), entrySourceID: nowPlaying.transitionSourceID, namespace: videoTransition,
           onDismiss: nowPlaying.finishDismissal) {
            Group {
                if let player = nowPlaying.livePlayer {
                    LiveRoomView(player: player, keepsPlaybackOnDismiss: true,
                                 onReturn: nowPlaying.dismissVideoPage)
                } else {
                    VideoPage()
                }
            }
                // 视频页有自己的 UIHostingController，不会继承根视图注入的文字
                // 档位（会退回跟随系统设置），必须在这里再补一次。
                .appTextSize()
                .background { VideoPagePresentationObserver(
                    onDidAppear: nowPlaying.videoPageDidAppear,
                    onInteractionBegan: nowPlaying.videoPageInteractionBegan,
                    onInteractionEnded: nowPlaying.videoPageInteractionEnded
                ) }
        }
        // 底部内容直接延伸，不加系统渐变模糊。
        .scrollEdgeEffectHidden(true, for: .bottom)
        .appTheme()
        .environment(nowPlaying)
        .environment(account)
        .environment(feedback)
        .environment(themeIcon)
        .environment(\.videoTransitionNamespace, videoTransition)
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

    private func submitSearch(_ keyword: String?) {
        search.submit(keyword: keyword)
        guard search.hasSubmittedSearch else { return }
        // 保持搜索 Tab 呈现，只收键盘，避免搜索框先退出底栏又进入导航栏。
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
        // 由 HomeTabReselectionObserver 单独接管，这里不插手。
        guard tab != displayedTab else { return }

        tabSwitchTask?.cancel()

        // 关注页由动态卡片负责入场，避免整页先淡入、数据就绪后卡片再入场。
        if tab == .search {
            searchReturnTab = displayedTab
        } else {
            isSearchFocused = false
            isSearchPresented = false
        }
        guard animatesPageEntrance, tab != .following, tab != .search else {
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
