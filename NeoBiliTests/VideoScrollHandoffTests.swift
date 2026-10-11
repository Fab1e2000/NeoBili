import UIKit
import XCTest
@testable import NeoBili

@MainActor
final class VideoScrollHandoffTests: XCTestCase {
    func testNativeOffsetConsumesHeaderThenListWithoutRewritingScroll() {
        let rig = Rig()
        rig.scroll.draggingForTest = true
        rig.move(120)
        XCTAssertEqual(rig.distance, 120)
        XCTAssertEqual(rig.observer.readingOffset, 0)
        XCTAssertEqual(rig.scroll.contentOffset.y, -180)
        rig.move(280)
        XCTAssertEqual(rig.distance, 200)
        XCTAssertEqual(rig.observer.readingOffset, 80)
        XCTAssertEqual(rig.scroll.contentOffset.y, -20)
    }

    func testReturnScrollReachesListTopBeforeExpanding() {
        let rig = Rig(); rig.scroll.draggingForTest = true
        rig.move(400)
        rig.move(250)
        XCTAssertEqual(rig.distance, 200)
        XCTAssertEqual(rig.observer.readingOffset, 50)
        rig.move(150)
        XCTAssertEqual(rig.distance, 150)
        XCTAssertEqual(rig.observer.readingOffset, 0)
    }

    func testPauseChangesRangeWithoutCancellingNativeInertia() {
        let rig = Rig(); rig.scroll.deceleratingForTest = true
        rig.move(300)
        let writes = rig.scroll.writes
        rig.maximum = 300 // Playing -> paused allows the control strip.
        rig.observer.configure(rig.geometry, page: .comments, ownsInsets: true)
        XCTAssertEqual(rig.scroll.writes, writes)
        rig.move(340)
        XCTAssertEqual(rig.distance, 240)
        XCTAssertEqual(rig.observer.readingOffset, 100)
    }

    func testInactivePageRestoresReadingPositionWhenSelected() {
        let rig = Rig(); rig.scroll.draggingForTest = true
        rig.move(400)
        rig.active = false
        rig.distance = 80
        rig.observer.configure(rig.geometry, page: .comments, ownsInsets: true)
        XCTAssertEqual(rig.scroll.contentOffset.y, 100)
        rig.active = true
        rig.observer.configure(rig.geometry, page: .comments, ownsInsets: true)
        XCTAssertEqual(rig.scroll.contentOffset.y, -20)
        XCTAssertEqual(rig.observer.readingOffset, 200)
    }

    func testTopBounceDoesNotCollapseAndInsetNeverAccumulates() {
        let rig = Rig(); rig.scroll.deceleratingForTest = true
        rig.move(-40); rig.move(-20)
        XCTAssertEqual(rig.distance, 0)
        let writes = rig.scroll.writes
        for _ in 0..<10 { rig.observer.configure(rig.geometry, page: .comments, ownsInsets: true) }
        XCTAssertEqual(rig.scroll.writes, writes, "Layout updates must not interrupt native top bounce")
        XCTAssertEqual(rig.scroll.contentOffset.y, -320)
        XCTAssertEqual(rig.scroll.contentInset.top, 300)
        rig.observer.detach()
        XCTAssertEqual(rig.scroll.contentInset.top, 0)
    }

    func testShortListPaddingTracksAsynchronousContentSize() {
        let rig = Rig()
        rig.scroll.contentSize.height = 100
        XCTAssertEqual(rig.scroll.contentInset.bottom, 400)
        rig.scroll.contentSize.height = 1200
        XCTAssertEqual(rig.scroll.contentInset.bottom, 0, "Loaded rows must remove short-list padding")
        rig.scroll.contentSize.height = 200
        XCTAssertEqual(rig.scroll.contentInset.bottom, 300)
    }

    func testHorizontalDragAndDecelerationDoNotMovePlayer() {
        let rig = Rig()
        let pager = TestScroll()
        pager.frame = rig.scroll.frame
        pager.contentSize = CGSize(width: 400, height: 500)
        pager.addSubview(rig.scroll)
        rig.scroll.deceleratingForTest = true
        pager.draggingForTest = true
        rig.move(100)
        XCTAssertEqual(rig.distance, 0)
        pager.draggingForTest = false
        pager.deceleratingForTest = true
        rig.move(140)
        XCTAssertEqual(rig.distance, 0)
        pager.deceleratingForTest = false
        rig.move(180)
        XCTAssertEqual(rig.distance, 40)
    }

    private final class Rig {
        let scroll = TestScroll()
        let observer = PausedVideoCollapseScroll.Observer()
        var distance: CGFloat = 0
        var maximum: CGFloat = 200
        var active = true
        var geometry: VideoScrollContext {
            .init(minimumContentHeight: 500, reservation: 300, distance: { [unowned self] in distance }, isActive: { [unowned self] _ in active })
        }
        init() {
            scroll.frame = CGRect(x: 0, y: 0, width: 200, height: 500)
            scroll.contentSize = CGSize(width: 200, height: 3000)
            observer.consume = { [unowned self] delta in
                let old = distance; distance = min(max(0, distance + delta), maximum); return distance - old
            }
            observer.canConsume = { [unowned self] delta in delta > 0 ? distance < maximum : distance > 0 }
            observer.configure(geometry, page: .comments, ownsInsets: true)
            scroll.addSubview(observer)
        }
        func move(_ normalized: CGFloat) { scroll.contentOffset.y = normalized - scroll.adjustedContentInset.top }
    }
    private final class TestScroll: UIScrollView {
        var draggingForTest = false
        var deceleratingForTest = false
        var writes = 0
        override var isDragging: Bool { draggingForTest }
        override var isDecelerating: Bool { deceleratingForTest }
        override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
            writes += 1; super.setContentOffset(contentOffset, animated: animated)
        }
    }
}
