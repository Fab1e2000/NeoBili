import Foundation
import CoreGraphics

/// playing 信号可能先于解码首帧到达，加载与真正暂停必须分开判断。
enum InlineVideoPlaybackPhase: Equatable {
    case loading
    case playing
    case paused

    init(isPlaying: Bool, hasRenderedFirstFrame: Bool, isLoading: Bool) {
        if !hasRenderedFirstFrame || isLoading {
            self = .loading
        } else {
            self = isPlaying ? .playing : .paused
        }
    }
}

/// 内联播放器随消费的滚动距离连续缩小；播放/加载停在标准画幅，
/// 只有已显示首帧的暂停视频才能继续缩至控制条并逐渐染色。
struct InlineVideoCollapseLayout: Equatable {
    let expandedHeight: CGFloat
    let compactHeight: CGFloat
    let minimumHeight: CGFloat

    var compactTravel: CGFloat { expandedHeight - compactHeight }

    init(expandedHeight: CGFloat, standardHeight: CGFloat, allowsCompact: Bool) {
        let expanded = expandedHeight.isFinite && expandedHeight > 0 ? expandedHeight : 0
        let minimum = min(56, expanded)
        let standard = standardHeight.isFinite && standardHeight > 0
            ? max(minimum, standardHeight)
            : expanded

        self.expandedHeight = expanded
        self.minimumHeight = minimum
        self.compactHeight = allowsCompact ? min(expanded, standard) : expanded
    }

    func maximumDistance(for phase: InlineVideoPlaybackPhase) -> CGFloat {
        switch phase {
        case .loading, .playing: compactTravel
        case .paused: expandedHeight - minimumHeight
        }
    }

    func constrainedDistance(_ distance: CGFloat, for phase: InlineVideoPlaybackPhase) -> CGFloat {
        min(clampedDistance(distance), maximumDistance(for: phase))
    }

    /// 元数据或窗口尺寸变化时保留可见高度；已经缩至标准尺寸则继续停在新的标准尺寸。
    func rebasedDistance(_ distance: CGFloat, from previous: Self, for phase: InlineVideoPlaybackPhase) -> CGFloat {
        guard distance > 0, previous.expandedHeight > 0 else { return 0 }
        if previous.compactTravel > 0, abs(distance - previous.compactTravel) <= 0.5 {
            return compactTravel
        }
        let visibleHeight = previous.containerHeight(for: distance)
        return constrainedDistance(expandedHeight - visibleHeight, for: phase)
    }

    func containerHeight(for distance: CGFloat) -> CGFloat {
        expandedHeight - clampedDistance(distance)
    }

    func surfaceHeight(for distance: CGFloat) -> CGFloat {
        // The render surface and its viewport use the same height throughout
        // both stages. A fixed compact-height surface plus a second negative
        // offset previously cropped/translated the image as the viewport shrank.
        containerHeight(for: distance)
    }

    func surfaceOffset(for distance: CGFloat) -> CGFloat {
        0
    }

    /// A single scroll-derived value for the whole header's tint and compact
    /// controls. Do not animate it on a separate clock or also fade the video:
    /// one tint overlay already reveals the final solid control strip at 1.
    func visualProgress(for distance: CGFloat, phase: InlineVideoPlaybackPhase) -> Double {
        guard phase == .paused else { return 0 }
        let tintTravel = compactHeight - minimumHeight
        guard tintTravel > 0 else { return 0 }
        let tintDistance = max(0, clampedDistance(distance) - compactTravel)
        return Double(min(tintDistance / tintTravel, 1))
    }

    func hidesVideo(for distance: CGFloat) -> Bool {
        // Intermediate paused frames remain visible and interactive; only the
        // fully opaque, minimum-height strip takes over their interaction.
        visualProgress(for: distance, phase: .paused) == 1
    }

    private func clampedDistance(_ distance: CGFloat) -> CGFloat {
        guard !distance.isNaN else { return 0 }
        return min(max(0, distance), expandedHeight - minimumHeight)
    }
}
