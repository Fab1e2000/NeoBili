import UIKit
import XCTest
@testable import NeoBili

@MainActor
final class VideoScrollHandoffTests: XCTestCase {
    func testDownwardDragFirstScrollsContentThenExpandsWithinSameGesture() {
        let rig = Rig(collapse: 200, offset: 50)
        rig.begin(downward: true)
        rig.drag(translation: 40, nativeOffset: 10)
        XCTAssertEqual(rig.collapse, 200)
        XCTAssertEqual(rig.scroll.contentOffset.y, 10)
        rig.drag(translation: 100, nativeOffset: -40)
        // Top is -30: of the next 60pt, 40 scrolls content and 20 expands.
        XCTAssertEqual(rig.collapse, 180)
        XCTAssertEqual(rig.scroll.contentOffset.y, -30)
    }

    func testFullyCollapsedStripCanExpandFromTopWithoutPlaying() {
        let rig = Rig(collapse: 200, offset: -30)
        rig.begin(downward: true)
        rig.drag(translation: 60, nativeOffset: -50)
        XCTAssertEqual(rig.collapse, 140)
        XCTAssertEqual(rig.scroll.contentOffset.y, -30)
    }

    func testPartialCollapseCanFullyExpandAndReleaseTheScroll() {
        let rig = Rig(collapse: 40, offset: -30)
        rig.begin(downward: true)
        rig.drag(translation: 70, nativeOffset: -55)
        XCTAssertEqual(rig.collapse, 0)
        XCTAssertEqual(rig.scroll.contentOffset.y, -30)
        rig.scroll.contentOffset.y = -45
        XCTAssertEqual(rig.scroll.contentOffset.y, -45, "Native overscroll is no longer locked")
    }

    func testUpwardCollapseStillHandsRemainderToContent() {
        let rig = Rig(collapse: 180, offset: -30)
        rig.begin(downward: false)
        rig.drag(translation: -50, nativeOffset: 20)
        XCTAssertEqual(rig.collapse, 200)
        XCTAssertEqual(rig.scroll.contentOffset.y, 0)
    }

    func testReversingAtTopUsesTheSameGesture() {
        let rig = Rig(collapse: 100, offset: -30)
        rig.begin(downward: false)
        rig.drag(translation: -40, nativeOffset: 10)
        XCTAssertEqual(rig.collapse, 140)
        rig.drag(translation: 10, nativeOffset: -60)
        XCTAssertEqual(rig.collapse, 90)
        XCTAssertEqual(rig.scroll.contentOffset.y, -30)
    }

    func testHorizontalPagingDoesNotResizePlayer() {
        let rig = Rig(collapse: 100, offset: -30)
        rig.observer.handlePan(state: .began, translation: .zero, velocity: CGPoint(x: 300, y: 20))
        rig.drag(translation: 30, nativeOffset: -40)
        XCTAssertEqual(rig.collapse, 100)
    }

    private final class Rig {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 500))
        let observer = PausedVideoCollapseScroll.Observer()
        var collapse: CGFloat
        init(collapse: CGFloat, offset: CGFloat) {
            self.collapse = collapse
            scroll.contentInsetAdjustmentBehavior = .never
            scroll.contentInset.top = 30
            scroll.contentSize = CGSize(width: 400, height: 1500)
            scroll.contentOffset.y = offset
            observer.canConsume = { [weak self] delta in
                guard let self else { return false }
                return delta < 0 ? self.collapse > 0 : self.collapse < 200
            }
            observer.consume = { [weak self] delta in
                guard let self else { return 0 }
                let old = self.collapse
                self.collapse = min(200, max(0, old + delta))
                return self.collapse - old
            }
            scroll.addSubview(observer)
        }
        func begin(downward: Bool) {
            observer.handlePan(state: .began, translation: .zero,
                               velocity: CGPoint(x: 0, y: downward ? 100 : -100))
        }
        func drag(translation: CGFloat, nativeOffset: CGFloat) {
            scroll.contentOffset.y = nativeOffset
            observer.handlePan(state: .changed, translation: CGPoint(x: 0, y: translation), velocity: .zero)
        }
    }
}
