import XCTest
@testable import NeoBili

final class FollowingSidebarPhysicsTests: XCTestCase {
    func testFingerTravelHasConstantGainAndCanReverseBeforeRelease() {
        for distance: CGFloat in [0, 6, 12, 24, 48, 72, 96] {
            XCTAssertEqual(FollowingSidebarPhysics.dragProgress(start: 0, translation: distance) * 96,
                           distance, accuracy: 0.00001)
        }
        XCTAssertEqual(FollowingSidebarPhysics.dragProgress(start: 0.65, translation: -24), 0.4, accuracy: 0.00001)
        XCTAssertEqual(FollowingSidebarPhysics.dragProgress(start: 0.65, translation: 0), 0.65)
        XCTAssertEqual(FollowingSidebarPhysics.dragProgress(start: 0, translation: -50), 0)
        XCTAssertEqual(FollowingSidebarPhysics.dragProgress(start: 1, translation: 50), 1)
    }

    func testReleaseProjectionAccountsForDirectionAndSpeed() {
        XCTAssertEqual(FollowingSidebarPhysics.target(progress: 0.2, velocity: 700), 1)
        XCTAssertEqual(FollowingSidebarPhysics.target(progress: 0.8, velocity: -700), 0)
        XCTAssertEqual(FollowingSidebarPhysics.target(progress: 0.49, velocity: 0), 0)
        XCTAssertEqual(FollowingSidebarPhysics.target(progress: 0.51, velocity: 0), 1)
    }

    func testSpringPreservesInitialVelocityAndDoesNotDependOnFrameRate() {
        let start = FollowingSidebarPhysics.Sample(progress: 0.3, velocity: 1.5)
        let immediate = FollowingSidebarPhysics.advance(start, toward: 1, elapsed: 0.000001)
        XCTAssertEqual((immediate.progress - start.progress) / 0.000001, start.velocity, accuracy: 0.001)
        var sixty = start
        var oneTwenty = start
        for _ in 0..<12 { sixty = FollowingSidebarPhysics.advance(sixty, toward: 1, elapsed: 1.0 / 60) }
        for _ in 0..<24 { oneTwenty = FollowingSidebarPhysics.advance(oneTwenty, toward: 1, elapsed: 1.0 / 120) }
        let delayed = FollowingSidebarPhysics.advance(start, toward: 1, elapsed: 0.2)
        XCTAssertEqual(sixty.progress, oneTwenty.progress, accuracy: 0.0000001)
        XCTAssertEqual(sixty.velocity, oneTwenty.velocity, accuracy: 0.0000001)
        XCTAssertEqual(sixty.progress, delayed.progress, accuracy: 0.0000001)
    }

    func testFastReversalsStayInsideTheScreenAndConverge() {
        for target: CGFloat in [0, 1] {
            for speed: CGFloat in [-60, -3, 0, 3, 60] {
                var sample = FollowingSidebarPhysics.Sample(progress: 0.5, velocity: speed)
                for _ in 0..<120 {
                    sample = FollowingSidebarPhysics.advance(sample, toward: target, elapsed: 1.0 / 120)
                    XCTAssertTrue((0...1).contains(sample.progress))
                }
                XCTAssertEqual(sample.progress, target, accuracy: 0.00001)
                XCTAssertEqual(sample.velocity, 0, accuracy: 0.00001)
            }
        }
    }

    func testScaledFeedFitsBothHorizontalEdgesAndRetainsFullViewportHeight() {
        for width: CGFloat in [40, 320, 393, 402, 430, 852] {
            for progress: CGFloat in [0, 0.25, 0.5, 0.75, 1] {
                let layout = FollowingFeedGeometry(width: width, height: 650, progress: progress)
                // 左侧展开时右缘等于屏宽；右侧展开时镜像后的左缘等于 0。
                XCTAssertEqual(layout.displacement + width * layout.scale, width, accuracy: 0.000001)
                XCTAssertEqual(width - width * layout.scale - layout.displacement, 0, accuracy: 0.000001)
                XCTAssertEqual(layout.unscaledHeight * layout.scale, 650, accuracy: 0.000001)
                XCTAssertGreaterThanOrEqual(layout.scale, 0.5)
            }
        }
    }

    @MainActor
    func testDraggingInterruptsSettleAtTheVisiblePositionWithoutAnAnimationJump() async throws {
        let motion = FollowingSidebarMotion()
        motion.drag(translation: 24)
        XCTAssertEqual(motion.progress, 0.25)
        XCTAssertTrue(motion.endDrag(velocity: 600, reduceMotion: false))
        try await Task.sleep(for: .milliseconds(30))
        let visible = motion.progress
        motion.drag(translation: -6)
        XCTAssertEqual(motion.progress, max(0, visible - 6.0 / 96), accuracy: 0.000001)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(motion.progress, max(0, visible - 6.0 / 96), accuracy: 0.000001,
                       "手指停住时旧动画不能继续推进")
        motion.reset()
        XCTAssertEqual(motion.progress, 0)
        XCTAssertFalse(motion.isDragging)
    }
}
