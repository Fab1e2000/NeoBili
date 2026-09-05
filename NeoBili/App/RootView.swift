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

struct RootView: View {
    @State private var nowPlaying = NowPlayingStore()
    @State private var account = AccountStore()
    @State private var feedback = ActionFeedback()
    @Namespace private var videoTransition

    /// 设置页那根滑杆选的档位。写在根视图上，改完立刻全 App 生效。
    @AppStorage(AppTextSize.storageKey) private var textSizeIndex = AppTextSize.defaultIndex

    var body: some View {
        @Bindable var nowPlaying = nowPlaying

        return TabView {
            Tab("推荐", systemImage: "house.fill") {
                HomeView()
            }
            // 搜索不再单独占一个 Tab：入口挪到了首页顶部那个常驻搜索框。
            Tab("关注", systemImage: "person.2.fill") {
                FollowingView()
            }
            Tab("我的", systemImage: "person.crop.circle") {
                MineView()
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
        // 全 App 的文字大小由设置页那根滑杆决定，不跟随系统的动态字体——
        // 两套缩放同时生效的话，同一个界面在不同设备上会被叠加缩放两次。
        // 在这里注入等于把系统档位整个覆盖掉。
        .dynamicTypeSize(AppTextSize.size(at: textSizeIndex))
        // 冷启动时用 Keychain 里可能存在的登录凭据恢复会话；
        // 「我的」页在恢复完成前不会闪出登录按钮。
        .task { await account.restoreSessionIfNeeded() }
    }
}

#Preview {
    RootView()
}
