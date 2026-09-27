import SwiftUI

/// 推荐流里点开的图文卡：按编号取动态详情，复用关注页的动态详情页。
/// 首页没有导航栈，所以从底部弹出，详情页右上角的关闭按钮直接收起它。
struct RecommendedDynamicSheet: View {
    let id: String
    @State private var entry: DynamicEntry?
    @State private var errorMessage: String?
    /// 详情页的点赞状态挂在一个动态列表模型上；这里单独给一个。
    @State private var feed = DynamicFeedModel(source: .following)
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if let entry {
                DynamicDetailView(entry: entry, feed: feed)
            } else {
                Group {
                    if let errorMessage {
                        ContentUnavailableView("无法打开这条动态", systemImage: "exclamationmark.triangle",
                                               description: Text(errorMessage))
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("关闭动态")
                    }
                }
            }
        }
        .task(id: id) {
            do {
                let item = try await BiliAPI.dynamicDetail(id: id)
                if let loaded = item.asEntry {
                    entry = loaded
                } else {
                    errorMessage = String(localized: "暂不支持这种动态")
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// 推荐卡片菜单里的「访问 UP 主页」：首页没有导航栈，把 UP 主页放进弹出页打开。
struct RecommendedSpaceSheet: View {
    let up: FollowedUp
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SpaceView(up: up)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("关闭")
                    }
                }
        }
    }
}
