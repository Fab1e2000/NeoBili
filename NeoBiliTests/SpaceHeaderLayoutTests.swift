import XCTest
@testable import NeoBili

final class SpaceHeaderLayoutTests: XCTestCase {
    func testPartiallyCollapsedHeaderAlignsBothPages() {
        XCTAssertEqual(SpaceHeaderLayout.synchronizedOffset(pageOffset: 0, collapse: 120, headerHeight: 300), 120)
        XCTAssertEqual(SpaceHeaderLayout.synchronizedOffset(pageOffset: 700, collapse: 120, headerHeight: 300), 120)
    }

    func testPinnedHeaderPreservesDeeperPagePosition() {
        XCTAssertEqual(SpaceHeaderLayout.synchronizedOffset(pageOffset: 700, collapse: 300, headerHeight: 300), 700)
        XCTAssertEqual(SpaceHeaderLayout.synchronizedOffset(pageOffset: 0, collapse: 300, headerHeight: 300), 300)
    }

    func testExpandedHeaderReturnsOtherPageToTop() {
        XCTAssertEqual(SpaceHeaderLayout.synchronizedOffset(pageOffset: 700, collapse: 0, headerHeight: 300), 0)
    }
}
