import SwiftUI

/// 三个信息流共用反馈；网络等待时旧内容仍然可见。
struct FeedRefreshFeedback: View {
    var isRefreshing: Bool
    var pullState: Int = 0
    var error: String?
    var retry: () -> Void

    var body: some View {
        Group {
            if isRefreshing {
                HStack(spacing: 8) { ProgressView(); Text("正在刷新") }
            } else if pullState > 0 {
                Label(pullState == 2 ? "松开刷新" : "下拉刷新",
                      systemImage: pullState == 2 ? "arrow.clockwise" : "arrow.down")
            } else if let error {
                HStack(spacing: 8) {
                    Text("刷新失败").accessibilityLabel("刷新失败：\(error)")
                    Button("重试", action: retry).frame(minWidth: 44, minHeight: 44)
                }
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background {
            if isRefreshing || pullState > 0 || error != nil {
                Capsule().fill(Color(uiColor: .secondarySystemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            }
        }
        .padding(.top, 8)
    }
}
