@testable import NeoBiliData
@testable import NeoBiliDomain
import XCTest
@testable import NeoBili

final class RemovalFillTests: XCTestCase {
    func testRemovalKeepsRelativeOrder() {
        XCTAssertTrue(RemovalFill.isRemovalOnly([1, 2, 3, 4], [1, 3]))
        XCTAssertTrue(RemovalFill.isRemovalOnly([1, 2], []))
        XCTAssertFalse(RemovalFill.isRemovalOnly([1, 2, 3], [1, 2, 3]))
        XCTAssertFalse(RemovalFill.isRemovalOnly([1, 2, 3], [3, 1]))
        XCTAssertFalse(RemovalFill.isRemovalOnly([Int](), [1]))
        XCTAssertFalse(RemovalFill.isRemovalOnly([Int](), [Int]()))
    }

    func testInlineRestoreIsNotAPageAppend() {
        XCTAssertTrue(RemovalFill.isInlineInsertion([1, 3], [1, 2, 3]))
        XCTAssertFalse(RemovalFill.isInlineInsertion([1, 2], [1, 2, 3]))
        XCTAssertFalse(RemovalFill.isInlineInsertion([Int](), [1]))
        XCTAssertTrue(RemovalFill.isOrderPreservingInsertion([1, 2], [1, 2, 3]))
        XCTAssertFalse(RemovalFill.isOrderPreservingInsertion([1, 3], [3, 1, 2]))
    }

    func testScopesLeavePaginationInstant() {
        XCTAssertTrue(RemovalFill.shouldAnimate(from: [1, 2, 3], to: [1, 3], scope: .removal))
        XCTAssertFalse(RemovalFill.shouldAnimate(from: [1, 2], to: [1, 2, 3], scope: .removal))
        XCTAssertFalse(RemovalFill.shouldAnimate(from: [Int](), to: [1, 2], scope: .removal))
        XCTAssertFalse(RemovalFill.shouldAnimate(from: [1, 2], to: [1, 2, 3], scope: .removalAndInlineRestore))
        XCTAssertTrue(RemovalFill.shouldAnimate(from: [1, 3], to: [1, 2, 3], scope: .removalAndInlineRestore))
        XCTAssertTrue(RemovalFill.shouldAnimate(from: [1, 2, 3], to: [], scope: .removalAndInlineRestore))
    }
}
