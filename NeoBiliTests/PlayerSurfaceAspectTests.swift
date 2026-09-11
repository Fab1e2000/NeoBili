import XCTest
@testable import NeoBili

final class PlayerSurfaceAspectTests: XCTestCase {
    func testDisplayAspectAccountsForRotation() {
        XCTAssertEqual(PlayerSurfaceGeometry.displayAspectRatio(16.0 / 9, rotation: 90)!, 9.0 / 16, accuracy: 0.000_001)
        XCTAssertEqual(PlayerSurfaceGeometry.displayAspectRatio(16.0 / 9, rotation: -90)!, 9.0 / 16, accuracy: 0.000_001)
        XCTAssertEqual(PlayerSurfaceGeometry.displayAspectRatio(16.0 / 9, rotation: 180)!, 16.0 / 9, accuracy: 0.000_001)
        XCTAssertNil(PlayerSurfaceGeometry.displayAspectRatio(.nan, rotation: 0))
        XCTAssertNil(PlayerSurfaceGeometry.displayAspectRatio(0, rotation: 0))
    }

    func testVideoContentFitsInlineAndFullscreenContainersWithoutCropping() {
        let surface = CGSize(width: 874, height: 402)
        let ratios: [Double] = [9.0 / 16, 1, 4.0 / 3, 16.0 / 9, 2.4, 3.0]
        for ratio in ratios {
            let containers = [
                CGSize(width: 402, height: min(402 / ratio, 560)),
                CGSize(width: 402, height: 226),
                CGSize(width: 402, height: 874),
                surface
            ]
            for container in containers {
                let scale = PlayerSurfaceGeometry.presentationScale(
                    surfaceSize: surface, containerSize: container, videoAspectRatio: ratio
                )
                let width = min(surface.width, surface.height * ratio) * scale
                let height = width / ratio
                XCTAssertLessThanOrEqual(width, container.width + 0.000_001)
                XCTAssertLessThanOrEqual(height, container.height + 0.000_001)
                XCTAssertTrue(abs(width - container.width) < 0.000_001 || abs(height - container.height) < 0.000_001)
            }
        }
    }
}
