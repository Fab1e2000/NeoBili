#if canImport(NeoBiliData)
@testable import NeoBiliData
#endif
#if canImport(NeoBiliDomain)
@testable import NeoBiliDomain
#endif
import XCTest
@testable import NeoBili

final class ResolvedContextMenuTests: XCTestCase {
    func testANewPressOverridesTheCardRememberedByTheMenu() {
        let now = Date(timeIntervalSinceReferenceDate: 20)
        let pressed = now.addingTimeInterval(-0.2)
        XCTAssertEqual(ResolvedContextMenu.finger("second", at: pressed, now: now), "second")
    }

    func testAnOldPressIsDiscarded() {
        let now = Date(timeIntervalSinceReferenceDate: 100)
        let pressed = now.addingTimeInterval(-30)
        XCTAssertNil(ResolvedContextMenu.finger("first", at: pressed, now: now))
    }

    func testSmallestRectWinsWhenFramesOverlap() {
        let rects = [
            "row": CGRect(x: 0, y: 20, width: 100, height: 40),
            "page": CGRect(x: 0, y: 0, width: 100, height: 200),
        ]
        XCTAssertEqual(ResolvedContextMenu.container(at: CGPoint(x: 10, y: 30), rects: rects), "row")
        XCTAssertNil(ResolvedContextMenu.container(at: CGPoint(x: 10, y: 10), rects: ["row": CGRect(x: 0, y: 20, width: 100, height: 40)]))
    }
}
