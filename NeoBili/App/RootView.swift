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
    @Namespace private var videoTransition

    var body: some View {
        @Bindable var nowPlaying = nowPlaying

        return TabView {
            Tab("推荐", systemImage: "house.fill") {
                HomeView()
            }
            Tab("搜索", systemImage: "magnifyingglass") {
                SearchView()
            }
        }
        // 视频页由最外层持有，播放器和整页状态统一由 NowPlayingStore 管理；
        // 视频页退出时由 store 负责停止并释放播放器。
        .fullScreenCover(isPresented: $nowPlaying.isExpanded) {
            VideoPage()
                .navigationTransition(
                    .zoom(sourceID: nowPlaying.transitionSourceID, in: videoTransition)
                )
        }
        .environment(nowPlaying)
        .environment(\.videoTransitionNamespace, videoTransition)
    }
}

#Preview {
    RootView()
}
