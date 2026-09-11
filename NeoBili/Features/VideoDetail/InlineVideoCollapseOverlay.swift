import SwiftUI

/// 一个连续色层覆盖状态栏、画面和下缘间距，全部由同一段滚动距离驱动。
struct InlineVideoCollapseOverlay: View {
    let progress: Double
    let videoHeight: CGFloat
    let topInset: CGFloat
    let isCollapsed: Bool
    let onExpand: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Color.accentColor
                .frame(height: videoHeight + topInset + 10)
                .offset(y: -topInset)
                .opacity(progress)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            Button(action: onExpand) {
                Image(systemName: "play.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .frame(maxWidth: .infinity)
                    .frame(height: videoHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(progress)
            .allowsHitTesting(isCollapsed)
            .accessibilityHidden(!isCollapsed)
            .accessibilityLabel("展开视频并继续播放")
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}
