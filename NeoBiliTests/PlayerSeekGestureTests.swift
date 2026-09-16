import XCTest
@testable import NeoBili

final class PlayerSeekGestureTests: XCTestCase {
    func testDraggingRightAndLeftUsesTheStartingPosition() throws {
        var state = try XCTUnwrap(PlayerSeekGestureState(position: 100, duration: 600, width: 300, translation: 18))
        state.update(translation: 118, location: CGPoint(x: 180, y: 100), height: 200)
        XCTAssertEqual(state.target, 130, accuracy: 0.001)
        state.update(translation: -82, location: CGPoint(x: 80, y: 100), height: 200)
        XCTAssertEqual(state.target, 70, accuracy: 0.001)
        XCTAssertEqual(state.delta, -30, accuracy: 0.001)
    }

    func testRecognitionDoesNotJumpAndReturningToOriginDoesNotDrift() throws {
        var state = try XCTUnwrap(PlayerSeekGestureState(position: 5, duration: 600, width: 300, translation: 20))
        XCTAssertEqual(state.target, 5)
        state.update(translation: -280, location: CGPoint(x: 0, y: 100), height: 200)
        XCTAssertEqual(state.target, 0)
        state.update(translation: 20, location: CGPoint(x: 160, y: 100), height: 200)
        XCTAssertEqual(state.target, 5, "到达开头后反向滑回起点，不能累积截断误差")
    }

    func testShortVideosUseTheirDurationAndNeverOvershoot() throws {
        var state = try XCTUnwrap(PlayerSeekGestureState(position: 5, duration: 10, width: 300, translation: 0))
        state.update(translation: 30, location: CGPoint(x: 180, y: 100), height: 200)
        XCTAssertEqual(state.target, 6, accuracy: 0.001)
        state.update(translation: 600, location: CGPoint(x: 300, y: 100), height: 200)
        XCTAssertEqual(state.target, 10)
    }

    func testTopCornersCancelButTheTopCentreDoesNot() throws {
        var state = try XCTUnwrap(PlayerSeekGestureState(position: 100, duration: 600, width: 300, translation: 0))
        for x in [CGFloat(10), CGFloat(290)] {
            state.update(translation: 30, location: CGPoint(x: x, y: 10), height: 200)
            XCTAssertTrue(state.isCancelled)
        }
        state.update(translation: 30, location: CGPoint(x: 150, y: 10), height: 200)
        XCTAssertFalse(state.isCancelled)
        XCTAssertEqual(state.target, 109, accuracy: 0.001)
    }

    func testUnknownDurationAndInvalidSnapshotsCannotStartSeeking() {
        XCTAssertNil(PlayerSeekGestureState(position: 0, duration: 0, width: 300, translation: 0))
        XCTAssertNil(PlayerSeekGestureState(position: .nan, duration: 100, width: 300, translation: 0))
        XCTAssertNil(PlayerSeekGestureState(position: 0, duration: .infinity, width: 300, translation: 0))
        XCTAssertNil(PlayerSeekGestureState(position: 0, duration: 100, width: 0, translation: 0))
    }
}
