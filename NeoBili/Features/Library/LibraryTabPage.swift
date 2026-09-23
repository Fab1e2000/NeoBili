import SwiftUI

/// 标签栏里的稍后再看、收藏、历史。列表本身与「我的」卡片里的是同一个视图，
/// 这里只换外壳：自己的导航栈、与其它主页面一致的固定页头（标题 + 头像），
/// 视频由根视图统一呈现。
struct LibraryTabPage: View {
    let tab: MainTab
    @AppStorage(TitleBarSettings.storageKey) private var pinsTitleBar = TitleBarSettings.defaultValue

    private var transitionID: String { "mine-avatar-\(tab.rawValue)" }

    var body: some View {
        NavigationStack {
            content
                // 根页用页头代替导航栏；推入的子页面（如收藏夹内容）仍显示自己的导航栏。
                .toolbar(.hidden, for: .navigationBar)
                // 固定标题栏挂在顶部栏；随内容滚动时交给列表，由列表放在内容第一行。
                .safeAreaBar(edge: .top, spacing: 0) {
                    if pinsTitleBar {
                        PageHeader(title: tab.pageTitle, transitionID: transitionID)
                            .padding(.horizontal, 20)
                    }
                }
                .environment(\.scrollingPageHeader, pinsTitleBar ? nil : ScrollingPageHeader(
                    title: tab.pageTitle, transitionID: transitionID))
                .onAppear { OrientationController.enterPortrait() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .watchLater: WatchLaterView()
        case .favorites: FavoritesView()
        case .history: HistoryView()
        default: EmptyView()
        }
    }
}
