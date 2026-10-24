import SwiftUI

/// 标签栏里的稍后再看、收藏、历史。列表本身与「我的」卡片里的是同一个视图，
/// 这里只换外壳：自己的导航栈、与其它主页面一致的原生大标题（标题 + 头像），
/// 视频由根视图统一呈现。
struct LibraryTabPage: View {
    let tab: MainTab

    var body: some View {
        NavigationStack {
            content
                // 根页使用原生栏内大标题；推入的子页面（如收藏夹内容）仍显示自己的导航栏。
                .rootPageChrome(title: tab.pageTitle)
                .onAppear { OrientationController.enterPortrait() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .watchLater: WatchLaterView(isTabRoot: true)
        case .favorites: FavoritesView(isTabRoot: true)
        case .history: HistoryView(isTabRoot: true)
        default: EmptyView()
        }
    }
}
