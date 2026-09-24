import SwiftUI

/// 一个连续色层覆盖状态栏、画面和下缘间距，全部由同一段滚动距离驱动。
struct InlineVideoCollapseOverlay: View {
    @Environment(\.appThemeColor) private var themeColor
    let progress: Double
    let videoHeight: CGFloat
    let topInset: CGFloat
    let bottomGap: CGFloat
    let isCollapsed: Bool
    let player: PlayerViewModel?
    let onBack: () -> Void
    let onExpand: () -> Void

    private var playTitle: String {
        guard let player, player.hasRenderedFirstFrame else { return String(localized: "立即播放") }
        return player.isPlaybackCompleted ? String(localized: "重新播放") : String(localized: "继续播放")
    }

    var body: some View {
        ZStack(alignment: .top) {
            themeColor
                .frame(height: videoHeight + topInset + bottomGap)
                .offset(y: -topInset)
                .opacity(progress)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            HStack(spacing: 0) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("返回")

                Button(action: onExpand) {
                    Label(playTitle, systemImage: player?.isPlaybackCompleted == true ? "arrow.counterclockwise" : "play.fill")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("展开视频并\(playTitle)")

                Color.clear.frame(width: 44, height: 44)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 8)
            .font(.title3)
            .foregroundStyle(.white)
            .frame(height: videoHeight)
            .buttonStyle(.plain)
            .opacity(progress)
            .allowsHitTesting(isCollapsed)
            .accessibilityHidden(!isCollapsed)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}
