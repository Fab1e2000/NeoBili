import SwiftUI
import XCTest
@testable import NeoBili

@MainActor
final class VideoCollapseMotionTests: XCTestCase {
    /// 布局未变化时按当前布局限位，和重构前渲染那一帧的换算一致。
    func testMotionUsesConstrainedDistanceWhileLayoutIsCurrent() {
        let layout = InlineVideoCollapseLayout(expandedHeight: 400, standardHeight: 300, allowsCompact: false)
        let motion = VideoCollapseMotion()
        motion.distance = 120
        XCTAssertEqual(motion.resolvedDistance(layout: layout, previousLayout: layout, phase: .playing),
                       layout.constrainedDistance(120, for: .playing))
        motion.distance = 10_000
        XCTAssertEqual(motion.resolvedDistance(layout: layout, previousLayout: layout, phase: .paused),
                       layout.constrainedDistance(10_000, for: .paused))
    }

    /// 布局刚变化、上一份布局还没更新的那一帧，沿用旧布局换算可见高度。
    func testMotionRebasesFromPreviousLayoutUntilChangeIsApplied() {
        let previous = InlineVideoCollapseLayout(expandedHeight: 400, standardHeight: 300, allowsCompact: false)
        let current = InlineVideoCollapseLayout(expandedHeight: 500, standardHeight: 300, allowsCompact: false)
        let motion = VideoCollapseMotion()
        motion.distance = 100
        XCTAssertEqual(motion.resolvedDistance(layout: current, previousLayout: previous, phase: .paused),
                       current.rebasedDistance(100, from: previous, for: .paused))
    }

    /// 暂停收起后刚恢复播放：距离超过标准画幅时，换算结果把画面恢复到完整尺寸。
    func testMotionMatchesPlaybackTransitionClamping() {
        let layout = InlineVideoCollapseLayout(expandedHeight: 400, standardHeight: 300, allowsCompact: true)
        let motion = VideoCollapseMotion()
        motion.distance = 350
        let rebased = motion.resolvedDistance(layout: layout, previousLayout: layout, phase: .paused)
        XCTAssertEqual(layout.distanceAfterPlaybackChange(rebased, to: .playing), 0)
    }
}
