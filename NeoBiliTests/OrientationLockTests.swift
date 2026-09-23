import XCTest
import UIKit
@testable import NeoBili

@MainActor
final class OrientationLockTests: XCTestCase {
    func testBackgroundPortraitRequestCannotInterruptFullscreen() {
        let lock = OrientationLock()
        let owner = UUID()
        XCTAssertTrue(lock.request(.landscape, owner: owner))
        XCTAssertFalse(lock.request(.portrait))
        XCTAssertEqual(lock.supportedOrientations, .landscape)
        XCTAssertTrue(lock.endPlayback(owner: owner))
        XCTAssertEqual(lock.supportedOrientations, .portrait)
        XCTAssertNil(lock.playbackOwner)
    }

    func testRepeatedAspectRatioUpdatesDoNotRepeatGeometryRequest() {
        let lock = OrientationLock()
        let owner = UUID()
        XCTAssertTrue(lock.request(.landscape, owner: owner))
        XCTAssertFalse(lock.request(.landscape, owner: owner))
        XCTAssertTrue(lock.request(.portrait, owner: owner))
        XCTAssertFalse(lock.request(.landscape))
        XCTAssertEqual(lock.supportedOrientations, .portrait)
        XCTAssertFalse(lock.endPlayback(owner: owner))
        XCTAssertNil(lock.playbackOwner)
        XCTAssertTrue(lock.request(.landscape))
    }

    func testDisappearingOldPlayerCannotReleaseNewPlayersOrientation() {
        let lock = OrientationLock()
        let old = UUID(), current = UUID()
        XCTAssertTrue(lock.request(.landscape, owner: old))
        XCTAssertFalse(lock.request(.landscape, owner: current))
        XCTAssertFalse(lock.endPlayback(owner: old))
        XCTAssertEqual(lock.playbackOwner, current)
        XCTAssertEqual(lock.supportedOrientations, .landscape)
        XCTAssertTrue(lock.endPlayback(owner: current))
    }
}
