import XCTest
import CoreGraphics
@testable import NeoBili

final class InlineVideoCollapseTests: XCTestCase {
    private let portrait = InlineVideoCollapseLayout(
        expandedHeight: 554, standardHeight: 221, allowsCompact: true
    )

    func testLoadingCannotBeMistakenForPausedOrForEarlyPlayingSignal() {
        for playing in [false, true] {
            for loading in [false, true] {
                XCTAssertEqual(InlineVideoPlaybackPhase(isPlaying: playing, hasRenderedFirstFrame: false, isLoading: loading), .loading)
            }
            XCTAssertEqual(InlineVideoPlaybackPhase(isPlaying: playing, hasRenderedFirstFrame: true, isLoading: true), .loading)
        }
        XCTAssertEqual(InlineVideoPlaybackPhase(isPlaying: true, hasRenderedFirstFrame: true, isLoading: false), .playing)
        XCTAssertEqual(InlineVideoPlaybackPhase(isPlaying: false, hasRenderedFirstFrame: true, isLoading: false), .paused)
    }

    func testLoadingPortraitStopsAtStandardFrameAndNeverUsesHiddenStrip() {
        XCTAssertEqual(portrait.maximumDistance(for: .loading), 333)
        for draggedDistance: CGFloat in [0, 166.5, 333, 400, 498, .infinity] {
            let distance = portrait.constrainedDistance(draggedDistance, for: .loading)
            XCTAssertGreaterThanOrEqual(portrait.containerHeight(for: distance), 221)
            XCTAssertEqual(portrait.surfaceHeight(for: distance), portrait.containerHeight(for: distance))
            XCTAssertEqual(portrait.surfaceOffset(for: distance), 0)
            XCTAssertFalse(portrait.hidesVideo(for: distance))
        }
    }

    func testLoadingLandscapeRetainsItsEntireActualFrame() {
        for height: CGFloat in [167, 221, 295] {
            let layout = InlineVideoCollapseLayout(expandedHeight: height, standardHeight: 221, allowsCompact: false)
            XCTAssertEqual(layout.maximumDistance(for: .loading), 0)
            let distance = layout.constrainedDistance(.infinity, for: .loading)
            XCTAssertEqual(distance, 0)
            XCTAssertEqual(layout.containerHeight(for: distance), height)
            XCTAssertEqual(layout.surfaceHeight(for: distance), height)
            XCTAssertFalse(layout.hidesVideo(for: distance))
            XCTAssertGreaterThan(layout.maximumDistance(for: .paused), 0)
        }
    }

    func testLateMetadataPreservesCompactIntentOrVisibleHeightWithinNewLimits() {
        let refined = InlineVideoCollapseLayout(expandedHeight: 610, standardHeight: 227, allowsCompact: true)
        let compact = refined.rebasedDistance(333, from: portrait, for: .loading)
        XCTAssertEqual(compact, refined.compactTravel)
        XCTAssertEqual(refined.containerHeight(for: compact), 227)
        let partial = refined.rebasedDistance(166.5, from: portrait, for: .loading)
        XCTAssertEqual(refined.containerHeight(for: partial), 387.5)

        let unknown = InlineVideoCollapseLayout(expandedHeight: 221, standardHeight: 221, allowsCompact: false)
        XCTAssertEqual(portrait.rebasedDistance(0, from: unknown, for: .loading), 0,
                       "未拖动的未知画幅在获得竖屏尺寸后正常展开")
        let wide = InlineVideoCollapseLayout(expandedHeight: 167, standardHeight: 221, allowsCompact: false)
        XCTAssertEqual(wide.rebasedDistance(498, from: portrait, for: .loading), 0)
        XCTAssertEqual(wide.rebasedDistance(498, from: portrait, for: .playing), 0)
        XCTAssertEqual(wide.rebasedDistance(498, from: portrait, for: .paused), 111)
    }

    func testReloadingOrResumingAHiddenPausedVideoImmediatelyRestoresFullSurface() {
        let hidden = portrait.maximumDistance(for: .paused)
        XCTAssertTrue(portrait.hidesVideo(for: hidden))
        for phase: InlineVideoPlaybackPhase in [.loading, .playing] {
            let restored = portrait.constrainedDistance(hidden, for: phase)
            XCTAssertEqual(restored, 333)
            XCTAssertEqual(portrait.containerHeight(for: restored), 221)
            XCTAssertFalse(portrait.hidesVideo(for: restored))
        }
        let firstFrameWhilePaused = InlineVideoPlaybackPhase(isPlaying: false, hasRenderedFirstFrame: true, isLoading: false)
        XCTAssertEqual(portrait.maximumDistance(for: firstFrameWhilePaused), 498)
    }

    func testPlayingPortraitCanShrinkToStandardHeightWithoutHidingVideo() {
        let distance = portrait.maximumDistance(for: .playing)

        XCTAssertEqual(portrait.compactHeight, 221)
        XCTAssertEqual(distance, 333)
        XCTAssertEqual(portrait.containerHeight(for: distance), 221)
        XCTAssertEqual(portrait.surfaceHeight(for: distance), 221)
        XCTAssertEqual(portrait.surfaceOffset(for: distance), 0)
        XCTAssertFalse(portrait.hidesVideo(for: distance))
    }

    func testIntermediateCompactGestureShrinksWholeSurfaceWithoutCropping() {
        for distance: CGFloat in [0, 83.25, 166.5, 249.75, 333] {
            XCTAssertEqual(
                portrait.surfaceHeight(for: distance),
                portrait.containerHeight(for: distance)
            )
            XCTAssertEqual(portrait.surfaceOffset(for: distance), 0)
            XCTAssertFalse(portrait.hidesVideo(for: distance))
        }
        XCTAssertEqual(portrait.containerHeight(for: 166.5), 387.5)
    }

    func testPausedPortraitContinuesFromCompactHeightToControlStrip() {
        let distance = portrait.maximumDistance(for: .paused)

        XCTAssertEqual(distance, 498)
        XCTAssertEqual(portrait.minimumHeight, 56)
        XCTAssertEqual(portrait.containerHeight(for: distance), 56)
        XCTAssertEqual(portrait.surfaceHeight(for: distance), 56)
        XCTAssertEqual(portrait.surfaceOffset(for: distance), 0)
        XCTAssertTrue(portrait.hidesVideo(for: distance))

        XCTAssertEqual(portrait.containerHeight(for: 400), 154)
        XCTAssertEqual(portrait.surfaceHeight(for: 400), 154)
        XCTAssertEqual(portrait.surfaceOffset(for: 400), 0)
        XCTAssertFalse(portrait.hidesVideo(for: 400))
    }

    func testResumingPlaybackClampsHiddenVideoBackToCompactFrame() {
        let pausedDistance = portrait.maximumDistance(for: .paused)
        let resumedDistance = min(pausedDistance, portrait.maximumDistance(for: .playing))

        XCTAssertEqual(resumedDistance, 333)
        XCTAssertEqual(portrait.containerHeight(for: resumedDistance), 221)
        XCTAssertEqual(portrait.surfaceHeight(for: resumedDistance), 221)
        XCTAssertFalse(portrait.hidesVideo(for: resumedDistance))
    }

    func testLandscapeCannotShrinkWhilePlayingButKeepsPausedCollapse() {
        let landscape = InlineVideoCollapseLayout(
            expandedHeight: 221, standardHeight: 221, allowsCompact: false
        )

        XCTAssertEqual(landscape.maximumDistance(for: .playing), 0)
        XCTAssertEqual(landscape.compactTravel, 0)
        XCTAssertEqual(landscape.maximumDistance(for: .paused), 165)
        XCTAssertEqual(landscape.containerHeight(for: 165), 56)
        XCTAssertEqual(landscape.surfaceHeight(for: 165), 56)
        XCTAssertEqual(landscape.surfaceOffset(for: 165), 0)
        XCTAssertTrue(landscape.hidesVideo(for: 165))

        let disallowedPortrait = InlineVideoCollapseLayout(
            expandedHeight: 554, standardHeight: 221, allowsCompact: false
        )
        XCTAssertEqual(disallowedPortrait.compactHeight, 554)
        XCTAssertEqual(disallowedPortrait.maximumDistance(for: .playing), 0)
    }

    func testVideoInteractionRemainsAvailableUntilTheStripIsFullyOpaque() {
        for distance: CGFloat in [0, 333, 333.5, 333.6, 400, 497.9] {
            XCTAssertFalse(portrait.hidesVideo(for: distance))
            XCTAssertLessThan(portrait.visualProgress(for: distance, phase: .paused), 1)
        }
        XCTAssertTrue(portrait.hidesVideo(for: 498))
        XCTAssertEqual(portrait.visualProgress(for: 498, phase: .paused), 1)
    }

    func testPausedTintFollowsDistanceContinuouslyAndReversesWithoutSeparateState() {
        for fraction in [0.0, 0.001, 0.1, 0.5, 0.9, 0.999, 1.0, 0.75, 0.5, 0.01, 0.0] {
            let distance = portrait.compactTravel + CGFloat(fraction) * 165
            XCTAssertEqual(portrait.visualProgress(for: distance, phase: .paused), fraction, accuracy: 0.000_001)
            XCTAssertEqual(portrait.surfaceHeight(for: distance), portrait.containerHeight(for: distance))
            XCTAssertEqual(portrait.surfaceOffset(for: distance), 0)
        }
        XCTAssertEqual(portrait.visualProgress(for: 333.5, phase: .paused), 0.5 / 165, accuracy: 0.000_001,
                       "Crossing the old threshold must not instantly tint the entire player")
    }

    func testSurfaceGeometryHasNoChangeOfSlopeAtTheCompactBoundary() {
        let step: CGFloat = 0.01
        for center: CGFloat in [100, portrait.compactTravel, 450] {
            let before = portrait.surfaceHeight(for: center - step)
            let at = portrait.surfaceHeight(for: center)
            let after = portrait.surfaceHeight(for: center + step)
            XCTAssertEqual(before - at, step, accuracy: 0.000_001)
            XCTAssertEqual(at - after, step, accuracy: 0.000_001)
        }
    }

    func testLoadingAndPlayingNeverInheritPausedTintEvenBeforeDistanceIsClamped() {
        for phase: InlineVideoPlaybackPhase in [.loading, .playing] {
            for distance: CGFloat in [0, 333, 400, 498, .infinity, .nan] {
                XCTAssertEqual(portrait.visualProgress(for: distance, phase: phase), 0)
            }
        }
        let landscape = InlineVideoCollapseLayout(expandedHeight: 221, standardHeight: 221, allowsCompact: false)
        XCTAssertEqual(landscape.visualProgress(for: 82.5, phase: .paused), 0.5)
        XCTAssertFalse(landscape.hidesVideo(for: 82.5))
    }

    func testOutOfRangeGestureDistancesStayWithinLayoutBounds() {
        for distance: CGFloat in [-100, -.infinity, .nan] {
            XCTAssertEqual(portrait.containerHeight(for: distance), 554)
            XCTAssertEqual(portrait.surfaceHeight(for: distance), 554)
            XCTAssertEqual(portrait.surfaceOffset(for: distance), 0)
            XCTAssertFalse(portrait.hidesVideo(for: distance))
        }
        for distance: CGFloat in [999, .infinity] {
            XCTAssertEqual(portrait.containerHeight(for: distance), 56)
            XCTAssertEqual(portrait.surfaceHeight(for: distance), 56)
            XCTAssertEqual(portrait.surfaceOffset(for: distance), 0)
        }
    }

    func testInvalidAndVerySmallGeometryCannotProduceNegativeOrNonfiniteFrames() {
        for expanded: CGFloat in [0, -1, .nan, .infinity] {
            let layout = InlineVideoCollapseLayout(
                expandedHeight: expanded, standardHeight: 221, allowsCompact: true
            )
            XCTAssertEqual(layout.expandedHeight, 0)
            XCTAssertEqual(layout.minimumHeight, 0)
            XCTAssertEqual(layout.compactHeight, 0)
            XCTAssertEqual(layout.maximumDistance(for: .paused), 0)
            XCTAssertEqual(layout.containerHeight(for: .infinity), 0)
            XCTAssertEqual(layout.surfaceHeight(for: .nan), 0)
            XCTAssertEqual(layout.visualProgress(for: .infinity, phase: .paused), 0)
        }

        for standard: CGFloat in [0, -1, .nan, .infinity] {
            let layout = InlineVideoCollapseLayout(
                expandedHeight: 554, standardHeight: standard, allowsCompact: true
            )
            XCTAssertEqual(layout.compactHeight, 554)
            XCTAssertEqual(layout.maximumDistance(for: .playing), 0)
        }

        let tiny = InlineVideoCollapseLayout(
            expandedHeight: 40, standardHeight: 20, allowsCompact: true
        )
        XCTAssertEqual(tiny.minimumHeight, 40)
        XCTAssertEqual(tiny.compactHeight, 40)
        XCTAssertEqual(tiny.maximumDistance(for: .paused), 0)
        XCTAssertEqual(tiny.visualProgress(for: .infinity, phase: .paused), 0)

        let undersizedStandard = InlineVideoCollapseLayout(
            expandedHeight: 554, standardHeight: 32, allowsCompact: true
        )
        XCTAssertEqual(undersizedStandard.compactHeight, 56)
        XCTAssertEqual(undersizedStandard.maximumDistance(for: .playing), 498)

        let widerThanStandard = InlineVideoCollapseLayout(
            expandedHeight: 167, standardHeight: 221, allowsCompact: true
        )
        XCTAssertEqual(widerThanStandard.compactHeight, 167)
        XCTAssertEqual(widerThanStandard.maximumDistance(for: .playing), 0)
    }
}
