import NeoBiliDomain
import SwiftUI

/// 推荐流里点开的图文卡：按编号取动态详情，复用关注页的动态详情页。
/// 图文详情通过 sheet 呈现，右上角关闭按钮收起面板。
struct RecommendedDynamicSheet: View {
    @Environment(\.applicationServices) private var services
    @Environment(\.applicationStores) private var stores
    let id: String
    @State private var detail: (entry: DynamicEntry, feed: DynamicFeedModel)?
    @State private var errorMessage: String?
    @State private var canRetry = false
    @State private var retryGeneration = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if let detail {
                DynamicDetailView(entry: detail.entry, feed: detail.feed, services: services)
            } else {
                Group {
                    if let errorMessage {
                        ContentUnavailableView {
                            Label("无法打开这条动态", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(errorMessage)
                        } actions: {
                            if canRetry { Button("重试") { retryGeneration += 1 } }
                        }
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
        .task(id: [id, String(retryGeneration)]) {
            detail = nil
            errorMessage = nil
            canRetry = false
            do {
                let item = try await services.community.dynamicDetail(id: id)
                try Task.checkCancellation()
                if let loaded = item.asEntry {
                    detail = (loaded, DynamicFeedModel(source: .following, likeStore: stores.likes, services: services))
                } else {
                    errorMessage = String(localized: "暂不支持这种动态")
                }
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                canRetry = true
                errorMessage = error.loadFailureDescription
            }
        }
    }
}

/// 推荐菜单的「访问 UP 主页」通过独立导航栈的 sheet 呈现。
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
