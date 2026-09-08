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
        } else {
            self
        }
    }
}

/// 三个主页面。切换时旧页面整体渐隐、新页面逐渐显现。
enum MainTab: Hashable {
    case home, following, mine
}

struct RootView: View {
    @State private var nowPlaying = NowPlayingStore()
    @State private var account = AccountStore()
    @State private var feedback = ActionFeedback()
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var videoTransition

    /// 设置页那根滑杆选的档位。写在根视图上，改完立刻全 App 生效。
    @AppStorage(AppTextSize.storageKey) private var textSizeIndex = AppTextSize.defaultIndex
    /// 内容过滤同样在根视图转成环境值，所有列表即时响应设置变化。
    @AppStorage(PortraitVideoFilterSettings.storageKey) private var hidesPortraitVideos = PortraitVideoFilterSettings.defaultValue

    /// 主页面切换特效：新页面淡入，快慢用设置页那条「进入」滑杆。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AnimationSpeedSettings.enterSpeedKey) private var enterSpeed = AnimationSpeedSettings.defaultSpeed
    /// 当前页面。点下去立刻就换，高亮跟着立刻走。
    @State private var displayedTab: MainTab = .home
    /// 新页面的浓度：切换那一刻置 0，随后淡入。
    @State private var tabContentOpacity: Double = 1
    @State private var tabSwitchTask: Task<Void, Never>?

    var body: some View {
        @Bindable var nowPlaying = nowPlaying

        return TabView(selection: tabSelection) {
            Tab("推荐", systemImage: "house.fill", value: MainTab.home) {
                HomeView().opacity(tabContentOpacity)
            }
            // 搜索不再单独占一个 Tab：入口挪到了首页顶部那个常驻搜索框。
            Tab("关注", systemImage: "person.2.fill", value: MainTab.following) {
                FollowingView().id(account.sessionID).opacity(tabContentOpacity)
            }
            Tab("我的", systemImage: "person.crop.circle", value: MainTab.mine) {
                MineView().opacity(tabContentOpacity)
            }
        }
        // 提示浮层只包住 TabView，不要包住下面那个 fullScreenCover。
        //
        // 浮层内部带一个 `.animation(value:)`，把它套在 cover 外面时，每次提示
        // 出现/消失都会给整条链路（含 cover 和它的 zoom 转场）开一次动画事务，
        // 视频页重新 present 时会因此被构建两遍，出现两个渲染容器互相抢渲染层。
        .actionFeedbackOverlay()
        // 视频页由最外层持有，播放器和整页状态统一由 NowPlayingStore 管理；
        // 视频页退出时由 store 负责停止并释放播放器。
        .fullScreenCover(isPresented: Binding(
            get: { nowPlaying.isExpanded && !nowPlaying.isServiceSheetPresented },
            set: { if !nowPlaying.isServiceSheetPresented { nowPlaying.isExpanded = $0 } }
        )) {
            VideoPage()
                // 视频页有自己的 UIHostingController，不会继承根视图注入的文字
                // 档位（会退回跟随系统设置），必须在这里再补一次。
                .appTextSize()
                .navigationTransition(
                    .zoom(sourceID: nowPlaying.transitionSourceID, in: videoTransition)
                )
        }
        .environment(nowPlaying)
        .environment(account)
        .environment(feedback)
        .environment(\.videoTransitionNamespace, videoTransition)
        .environment(\.hidesPortraitVideos, hidesPortraitVideos)
        // 全 App 的文字大小由设置页那根滑杆决定，不跟随系统的动态字体——
        // 两套缩放同时生效的话，同一个界面在不同设备上会被叠加缩放两次。
        // 在这里注入等于把系统档位整个覆盖掉。
        .dynamicTypeSize(AppTextSize.size(at: textSizeIndex))
        // 冷启动时用 Keychain 里可能存在的登录凭据恢复会话；
        // 「我的」页在恢复完成前不会闪出登录按钮。
        .task { await account.restoreSessionIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await account.retrySessionIfNeeded() } }
        }
        .onChange(of: account.sessionID) { nowPlaying.close() }
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
        guard !reduceMotion, tab != .following else {
            tabContentOpacity = 1
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
}

#Preview {
    RootView()
}
