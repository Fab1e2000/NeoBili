import SwiftUI

/// 稿件标签，横向一排胶囊。
///
/// 标签数量不定，长标签也常见，所以整行可以横向滚动而不是折行——折行会让
/// 简介区高度随视频不同上下跳。左右留白用 `.contentMargins` 而不是给内容加
/// padding，这样滚到两端时胶囊不会被容器边缘切掉。
struct VideoTagsRow: View {
    let tags: [VideoTag]
    /// 和正文一致的左右留白。
    let horizontalInset: CGFloat

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(tags) { tag in
                    Text(tag.tagName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.background.secondary, in: Capsule())
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, horizontalInset, for: .scrollContent)
    }
}
