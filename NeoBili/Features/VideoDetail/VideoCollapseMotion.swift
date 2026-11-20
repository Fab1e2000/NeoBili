import SwiftUI

/// 视频页折叠距离的独立观察盒子。滚动逐帧只失效真正依赖它的子视图：
/// 播放器区域的裁切与可见性、收起覆盖层和顶部染色条；简介组件、评论画布与
/// 分页容器保持稳定，不随滚动重建。整体与 UP 主页头部的折叠观察方式一致。
@MainActor @Observable
final class VideoCollapseMotion {
    var distance: CGFloat = 0

    /// 当前布局下的实际折叠距离。布局刚变化、上一份布局还没更新的那一帧，
    /// 沿用旧布局换算可见高度，避免异步元数据与首帧不同拍时跳高。
    func resolvedDistance(layout: InlineVideoCollapseLayout,
                          previousLayout: InlineVideoCollapseLayout,
                          phase: InlineVideoPlaybackPhase) -> CGFloat {
        layout == previousLayout
            ? layout.constrainedDistance(distance, for: phase)
            : layout.rebasedDistance(distance, from: previousLayout, for: phase)
    }
}

/// 播放器区域。只有这一层随折叠距离重算高度、裁切与隐藏状态。
struct CollapsibleVideoSlot<Content: View>: View {
    let motion: VideoCollapseMotion
    let layout: InlineVideoCollapseLayout
    let previousLayout: InlineVideoCollapseLayout
    let phase: InlineVideoPlaybackPhase
    let isFullScreen: Bool
    let size: CGSize
    let content: (Bool) -> Content

    var body: some View {
        let distance = isFullScreen
            ? 0
            : motion.resolvedDistance(layout: layout, previousLayout: previousLayout, phase: phase)
        let height = isFullScreen ? size.height : layout.containerHeight(for: distance)
        let progress = isFullScreen ? 0 : layout.visualProgress(for: distance, phase: phase)
        content(!isFullScreen && layout.hidesVideo(for: distance))
            .frame(width: size.width, height: height)
            .allowsHitTesting(progress == 0)
            .accessibilityHidden(progress > 0)
            .frame(width: size.width, height: height)
            .clipped()
            .contentShape(Rectangle())
    }
}

/// 收起后的覆盖层：返回、继续播放与整块染色都由同一段距离驱动。
struct CollapseChromeSlot: View {
    let motion: VideoCollapseMotion
    let layout: InlineVideoCollapseLayout
    let previousLayout: InlineVideoCollapseLayout
    let phase: InlineVideoPlaybackPhase
    let topInset: CGFloat
    let player: PlayerViewModel?
    let onBack: () -> Void
    let onExpand: () -> Void

    var body: some View {
        let distance = motion.resolvedDistance(layout: layout, previousLayout: previousLayout, phase: phase)
        InlineVideoCollapseOverlay(
            progress: layout.visualProgress(for: distance, phase: phase),
            videoHeight: layout.containerHeight(for: distance),
            topInset: topInset,
            player: player,
            onBack: onBack,
            onExpand: onExpand
        )
    }
}

/// 内容区顶部圆角后方的主题色填充，随折叠进度渐显。
struct CollapsedThemeStrip: View {
    let motion: VideoCollapseMotion
    let layout: InlineVideoCollapseLayout
    let previousLayout: InlineVideoCollapseLayout
    let phase: InlineVideoPlaybackPhase
    let color: Color
    let height: CGFloat

    var body: some View {
        let distance = motion.resolvedDistance(layout: layout, previousLayout: previousLayout, phase: phase)
        color
            .opacity(layout.visualProgress(for: distance, phase: phase))
            .frame(height: height)
            .allowsHitTesting(false)
    }
}
