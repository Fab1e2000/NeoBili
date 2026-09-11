import Foundation

@main struct InlineVideoCollapseRegression {
    static func main() {
        let portrait = InlineVideoCollapseLayout(
            expandedHeight: 554, standardHeight: 221, allowsCompact: true
        )
        for playing in [false, true] {
            for loading in [false, true] {
                precondition(InlineVideoPlaybackPhase(isPlaying: playing, hasRenderedFirstFrame: false, isLoading: loading) == .loading)
            }
            precondition(InlineVideoPlaybackPhase(isPlaying: playing, hasRenderedFirstFrame: true, isLoading: true) == .loading)
        }
        precondition(InlineVideoPlaybackPhase(isPlaying: true, hasRenderedFirstFrame: true, isLoading: false) == .playing)
        precondition(InlineVideoPlaybackPhase(isPlaying: false, hasRenderedFirstFrame: true, isLoading: false) == .paused)
        print("PASS  加载、播放、暂停明确分离，playing 早于首帧仍属于加载")

        precondition(portrait.maximumDistance(for: .loading) == 333)
        for proposed: CGFloat in [0, 166.5, 333, 400, 498, .infinity] {
            let distance = portrait.constrainedDistance(proposed, for: .loading)
            precondition(portrait.containerHeight(for: distance) >= 221)
            precondition(portrait.surfaceHeight(for: distance) == portrait.containerHeight(for: distance))
            precondition(!portrait.hidesVideo(for: distance))
        }
        for height: CGFloat in [167, 221, 295] {
            let layout = InlineVideoCollapseLayout(expandedHeight: height, standardHeight: 221, allowsCompact: false)
            let distance = layout.constrainedDistance(.infinity, for: .loading)
            precondition(distance == 0)
            precondition(layout.containerHeight(for: distance) == height)
            precondition(!layout.hidesVideo(for: distance))
        }
        print("PASS  首帧前竖屏最多收至标准画幅，横屏保持实际画幅，均不会隐藏成粉条")

        let refined = InlineVideoCollapseLayout(expandedHeight: 610, standardHeight: 227, allowsCompact: true)
        let compact = refined.rebasedDistance(333, from: portrait, for: .loading)
        precondition(refined.containerHeight(for: compact) == 227)
        let partial = refined.rebasedDistance(166.5, from: portrait, for: .loading)
        precondition(refined.containerHeight(for: partial) == 387.5)
        let unknown = InlineVideoCollapseLayout(expandedHeight: 221, standardHeight: 221, allowsCompact: false)
        precondition(portrait.rebasedDistance(0, from: unknown, for: .loading) == 0)
        let wide = InlineVideoCollapseLayout(expandedHeight: 167, standardHeight: 221, allowsCompact: false)
        precondition(wide.rebasedDistance(498, from: portrait, for: .loading) == 0)
        precondition(wide.rebasedDistance(498, from: portrait, for: .playing) == 0)
        precondition(wide.rebasedDistance(498, from: portrait, for: .paused) == 111)
        print("PASS  迟到元数据保留标准尺寸或可见高度，旋转/换画幅不越过当前状态限制")

        precondition(portrait.maximumDistance(for: .playing) == 333)
        for distance: CGFloat in [0, 83.25, 166.5, 249.75, 333] {
            precondition(portrait.surfaceHeight(for: distance) == portrait.containerHeight(for: distance))
            precondition(portrait.surfaceOffset(for: distance) == 0)
            precondition(!portrait.hidesVideo(for: distance))
        }
        precondition(portrait.containerHeight(for: 333) == 221)
        precondition(portrait.surfaceHeight(for: 333) == 221)
        print("PASS  竖屏播放可连续缩至标准视频高度，完整画面不裁切且继续显示")

        let pausedDistance = portrait.maximumDistance(for: .paused)
        precondition(pausedDistance == 498)
        precondition(portrait.containerHeight(for: pausedDistance) == 56)
        precondition(portrait.surfaceHeight(for: pausedDistance) == 56)
        precondition(portrait.surfaceOffset(for: pausedDistance) == 0)
        precondition(portrait.hidesVideo(for: pausedDistance))
        precondition(!portrait.hidesVideo(for: 333.5))
        precondition(!portrait.hidesVideo(for: 333.6))
        precondition(portrait.visualProgress(for: 333.5, phase: .paused) == 0.5 / 165)
        for fraction in [0.0, 0.1, 0.5, 0.9, 1.0, 0.9, 0.5, 0.1, 0.0] {
            let distance = portrait.compactTravel + CGFloat(fraction) * 165
            precondition(abs(portrait.visualProgress(for: distance, phase: .paused) - fraction) < 0.000_001)
            precondition(portrait.surfaceHeight(for: distance) == portrait.containerHeight(for: distance))
            precondition(portrait.surfaceOffset(for: distance) == 0)
        }
        for phase: InlineVideoPlaybackPhase in [.loading, .playing] {
            precondition(portrait.visualProgress(for: pausedDistance, phase: phase) == 0)
        }
        let resumedDistance = min(pausedDistance, portrait.maximumDistance(for: .playing))
        precondition(portrait.containerHeight(for: resumedDistance) == 221)
        precondition(portrait.surfaceHeight(for: resumedDistance) == 221)
        precondition(!portrait.hidesVideo(for: resumedDistance))
        print("PASS  暂停后画面与单一染色进度连续收至56点，无标准尺寸处跳变，恢复播放清除染色")

        let landscape = InlineVideoCollapseLayout(
            expandedHeight: 221, standardHeight: 221, allowsCompact: false
        )
        precondition(landscape.maximumDistance(for: .playing) == 0)
        precondition(landscape.maximumDistance(for: .paused) == 165)
        precondition(landscape.containerHeight(for: 165) == 56)
        precondition(landscape.surfaceHeight(for: 165) == 56)
        precondition(landscape.surfaceOffset(for: 165) == 0)
        print("PASS  横屏播放保持原高度，暂停收起行为保留")

        for distance: CGFloat in [-100, -.infinity, .nan] {
            precondition(portrait.containerHeight(for: distance) == 554)
            precondition(portrait.surfaceHeight(for: distance) == 554)
            precondition(portrait.surfaceOffset(for: distance) == 0)
        }
        for distance: CGFloat in [999, .infinity] {
            precondition(portrait.containerHeight(for: distance) == 56)
            precondition(portrait.surfaceHeight(for: distance) == 56)
        }
        for expanded: CGFloat in [0, -1, .nan, .infinity] {
            let layout = InlineVideoCollapseLayout(
                expandedHeight: expanded, standardHeight: 221, allowsCompact: true
            )
            precondition(layout.minimumHeight == 0)
            precondition(layout.compactHeight == 0)
            precondition(layout.containerHeight(for: .infinity) == 0)
            precondition(layout.surfaceHeight(for: .nan) == 0)
        }
        for standard: CGFloat in [0, -1, .nan, .infinity] {
            let layout = InlineVideoCollapseLayout(
                expandedHeight: 554, standardHeight: standard, allowsCompact: true
            )
            precondition(layout.compactHeight == 554)
            precondition(layout.maximumDistance(for: .playing) == 0)
        }
        let tiny = InlineVideoCollapseLayout(
            expandedHeight: 40, standardHeight: 20, allowsCompact: true
        )
        precondition(tiny.minimumHeight == 40)
        precondition(tiny.compactHeight == 40)
        precondition(tiny.maximumDistance(for: .paused) == 0)
        print("PASS  越界手势、无效尺寸和极小容器不会产生负数或非有限布局")
    }
}
