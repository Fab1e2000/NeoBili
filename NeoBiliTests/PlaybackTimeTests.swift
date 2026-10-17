import XCTest
@testable import NeoBili

final class PlaybackTimeTests: XCTestCase {
    func testInvalidAndUnrepresentableTimesUseZeroFallback() {
        for value in [Double.nan, .infinity, -.infinity, -1, Double(Int.max), .greatestFiniteMagnitude] {
            XCTAssertEqual(PlaybackTime.text(value), "0:00")
        }
    }
    func testFiniteTimesKeepMinuteSecondFormatting() {
        XCTAssertEqual(PlaybackTime.text(0), "0:00")
        XCTAssertEqual(PlaybackTime.text(59.9), "0:59")
        XCTAssertEqual(PlaybackTime.text(3601), "60:01")
    }
}
