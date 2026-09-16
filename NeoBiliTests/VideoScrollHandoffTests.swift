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

    func testFlingReleasedBeforeTopContinuesIntoPlayerExpansion() {
        let rig = Rig(collapse: 200, offset: 150)
        rig.begin(downward: true)
        rig.drag(translation: 40, nativeOffset: 110)
        defer { rig.observer.detach() }
        rig.end(velocity: 1000)
        rig.observer.advanceMomentum(elapsed: 1.0 / 60)
        XCTAssertEqual(rig.collapse, 200, "列表未回顶前不能展开播放器")
        XCTAssertLessThan(rig.scroll.contentOffset.y, 110)
        for _ in 0..<120 { rig.observer.advanceMomentum(elapsed: 1.0 / 60) }
        XCTAssertEqual(rig.collapse, 0, accuracy: 0.01, "一次惯性完成回顶和展开，无需第二次手势")
        XCTAssertEqual(rig.scroll.contentOffset.y, -30, accuracy: 0.01)
    }

    func testWeakFlingStopsInContentWithoutPrematureExpansion() {
        let rig = Rig(collapse: 200, offset: 300)
        rig.begin(downward: true)
        defer { rig.observer.detach() }
        rig.end(velocity: 100)
        for _ in 0..<180 { rig.observer.advanceMomentum(elapsed: 1.0 / 60) }
        XCTAssertEqual(rig.collapse, 200)
        XCTAssertGreaterThan(rig.scroll.contentOffset.y, -30)
        XCTAssertLessThan(rig.scroll.contentOffset.y, 300)
    }

    func testCollapseMomentumContinuesIntoContentAtTheOtherEnd() {
        let rig = Rig(collapse: 100, offset: -30)
        rig.begin(downward: false)
        rig.drag(translation: -20, nativeOffset: -10)
        defer { rig.observer.detach() }
        rig.end(velocity: -800)
        for _ in 0..<120 { rig.observer.advanceMomentum(elapsed: 1.0 / 60) }
        XCTAssertEqual(rig.collapse, 200)
        XCTAssertGreaterThan(rig.scroll.contentOffset.y, 0)
    }

    func testNewTouchStopsPreviousExpansionMomentum() {
        let rig = Rig(collapse: 200, offset: 100)
        rig.begin(downward: true)
        defer { rig.observer.detach() }
        rig.end(velocity: 1000)
        rig.observer.advanceMomentum(elapsed: 1.0 / 60)
        let offset = rig.scroll.contentOffset.y
        rig.begin(downward: false)
        rig.observer.advanceMomentum(elapsed: 1.0 / 60)
        XCTAssertEqual(rig.scroll.contentOffset.y, offset)
        XCTAssertEqual(rig.collapse, 200)
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
        func end(velocity: CGFloat) {
            observer.handlePan(state: .ended, translation: .zero, velocity: CGPoint(x: 0, y: velocity))
        }
    }
}
