import XCTest
import CoreGraphics
@testable import NeoBili

final class InlineVideoLayoutTests: XCTestCase {
    private let portraitScreen = CGSize(width: 393, height: 852)

    func testInlineHeightFitsLandscapeSquareAndPortraitSources() {
        XCTAssertEqual(InlineVideoLayout.height(for: portraitScreen, aspectRatio: 16.0 / 9.0), 221)
        XCTAssertEqual(InlineVideoLayout.height(for: portraitScreen, aspectRatio: 4.0 / 3.0), 295)
        XCTAssertEqual(InlineVideoLayout.height(for: portraitScreen, aspectRatio: 2.35), 167)
        XCTAssertEqual(InlineVideoLayout.height(for: portraitScreen, aspectRatio: 1), 393)
        XCTAssertEqual(InlineVideoLayout.height(for: portraitScreen, aspectRatio: 0.8), 491)
        XCTAssertEqual(InlineVideoLayout.height(for: portraitScreen, aspectRatio: 9.0 / 16.0), 554)
    }

    func testTallVideoIsCappedToLeaveRoomForDetails() {
        let height = InlineVideoLayout.height(for: portraitScreen, aspectRatio: 0.1)
        XCTAssertEqual(height, (852 * 0.65).rounded())
        XCTAssertLessThan(height, portraitScreen.height - 250)
    }

    func testAllAspectRatiosKeepHeightAcrossRotation() {
        let landscapeScreen = CGSize(width: 852, height: 393)
        for ratio in [16.0 / 9.0, 4.0 / 3.0, 1, 9.0 / 16.0] {
            XCTAssertEqual(
                InlineVideoLayout.height(for: portraitScreen, aspectRatio: ratio),
                InlineVideoLayout.height(for: landscapeScreen, aspectRatio: ratio)
            )
        }
    }

    func testHidingPortraitVideosKeepsExistingSixteenByNineFrame() {
        for ratio in [4.0 / 3.0, 1, 9.0 / 16.0] {
            XCTAssertEqual(
                InlineVideoLayout.height(for: portraitScreen, aspectRatio: ratio, hidesPortraitVideos: true),
                221
            )
        }
    }

    func testUnknownAndInvalidDimensionsUseSixteenByNineUntilAvailable() {
        for ratio: Double? in [nil, 0, -1, .nan, .infinity] {
            XCTAssertEqual(InlineVideoLayout.height(for: portraitScreen, aspectRatio: ratio), 221)
        }
        XCTAssertNil(InlineVideoLayout.aspectRatio(width: 0, height: 1920))
        XCTAssertNil(InlineVideoLayout.aspectRatio(width: 1080, height: -1))
        XCTAssertEqual(InlineVideoLayout.height(for: .zero, aspectRatio: 1), 0)
    }

    func testRotationMetadataUsesDisplayDimensions() {
        XCTAssertEqual(InlineVideoLayout.aspectRatio(width: 1920, height: 1080), 16.0 / 9.0)
        for rotation in [90, 270, -90, 450] {
            XCTAssertEqual(InlineVideoLayout.aspectRatio(width: 1920, height: 1080, rotation: rotation), 9.0 / 16.0)
        }
        XCTAssertEqual(InlineVideoLayout.aspectRatio(width: 1920, height: 1080, rotation: 180), 16.0 / 9.0)
    }

    func testPartDimensionsDecodeIndependentlyAndRemainOptional() throws {
        let payload = Data("""
        [
          {"cid":1,"page":1,"part":"横屏","duration":10,"dimension":{"width":1920,"height":1080,"rotate":0}},
          {"cid":2,"page":2,"part":"竖屏","duration":20,"dimension":{"width":1080,"height":1920,"rotate":0}},
          {"cid":3,"page":3,"part":"未知","duration":30}
        ]
        """.utf8)
        let parts = try JSONDecoder().decode([VideoPart].self, from: payload)
        XCTAssertEqual(parts[0].dimension?.isPortrait, false)
        XCTAssertEqual(parts[1].dimension?.isPortrait, true)
        XCTAssertNil(parts[2].dimension)
    }
}
