import XCTest
@testable import NeoBili

final class VideoFullscreenOrientationTests: XCTestCase {
    func testPortraitSourceUsesPortraitFullscreenIncludingRotatedEncoding() {
        XCTAssertEqual(VideoFullscreenOrientation.preferred(for: 9.0 / 16), .portrait)
        let rotated = InlineVideoLayout.aspectRatio(width: 1920, height: 1080, rotation: 90)
        XCTAssertEqual(VideoFullscreenOrientation.preferred(for: rotated), .portrait)
    }

    func testLandscapeSquareAndUnknownSourcesKeepLandscapeFullscreen() {
        for ratio: Double? in [16.0 / 9, 2.4, 1, nil, 0, -1, .nan, .infinity] {
            XCTAssertEqual(VideoFullscreenOrientation.preferred(for: ratio), .landscape)
        }
    }
}
