import SwiftUI
import UIKit
import XCTest
@testable import NeoBili

@MainActor
final class PlayerInteractionRefinementTests: XCTestCase {
    func testContentDownwardPanBlocksZoomDismissButPreservesHorizontalAndOriginalDelegate() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        let pan = DirectionPan()
        let original = OriginalDelegate()
        pan.delegate = original
        controller.view.addGestureRecognizer(pan)
        let player = PlayerReturnGestureGuard.RegionView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let content = PlayerReturnGestureGuard.RegionView(frame: CGRect(x: 0, y: 100, width: 200, height: 400))
        content.verticalOnly = true
        controller.view.addSubview(player)
        controller.view.addSubview(content)
        let gate = try XCTUnwrap(pan.delegate as? PlayerReturnGestureGuard.DelegateGate)
        for _ in 0..<5 { player.install(); content.install() }
        XCTAssertTrue(pan.delegate === gate, "Both regions must share one delegate without overwriting each other")
        pan.direction = CGPoint(x: 1, y: 300)
        XCTAssertFalse(gate.gestureRecognizerShouldBegin(pan), "Initial downward drag must not start a zoom return")
        pan.direction = CGPoint(x: 300, y: 1)
        XCTAssertTrue(gate.gestureRecognizerShouldBegin(pan), "Horizontal return remains available")
        pan.direction = CGPoint(x: 0, y: 300)
        content.enabled = false
        XCTAssertTrue(gate.gestureRecognizerShouldBegin(pan))
        player.detach()
        XCTAssertTrue(pan.delegate === gate)
        content.detach()
        XCTAssertTrue(pan.delegate === original)
    }

    func testMovementBoundsStayValidForStoredInvalidValues() {
        for (top, bottom) in [(0.0, 1.0), (0.3, 0.9), (0.9, 0.1), (.nan, .infinity), (-1.0, 5.0)] {
            let limits = MiniPlayerMovementSettings.normalized(top: top, bottom: bottom)
            XCTAssertGreaterThanOrEqual(limits.top, 0)
            XCTAssertLessThanOrEqual(limits.bottom, 1)
            XCTAssertGreaterThanOrEqual(limits.bottom - limits.top + 0.000001, 0.45)
        }
    }

    func testMiniPlayerRepositionsAndFitsWithinUpdatedLimitsForBothAspects() {
        for ratio in [16.0 / 9, 9.0 / 16] {
            let controller = MiniPlayerContainerController(content: Color.clear)
            controller.configure(aspectRatio: ratio, anchor: CGPoint(x: 1, y: 1), reduceMotion: true, onAnchorChange: { _ in })
            controller.loadViewIfNeeded()
            controller.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
            controller.viewDidLayoutSubviews()
            controller.configure(aspectRatio: ratio, anchor: CGPoint(x: 1, y: 1), reduceMotion: true,
                                 topLimit: 0.25, bottomLimit: 0.75, onAnchorChange: { _ in })
            controller.viewDidLayoutSubviews()
            let bounds = MiniPlayerLayout.movementBounds(in: controller.view.safeAreaLayoutGuide.layoutFrame.insetBy(dx: 12, dy: 12),
                                                         top: 0.25, bottom: 0.75)
            XCTAssertTrue(bounds.insetBy(dx: -0.01, dy: -0.01).contains(controller.host.view.frame))
            XCTAssertEqual(controller.host.view.bounds.width / controller.host.view.bounds.height, ratio, accuracy: 0.001)
        }
    }
}

@MainActor
private final class DirectionPan: UIPanGestureRecognizer {
    var direction = CGPoint.zero
    override func velocity(in view: UIView?) -> CGPoint { direction }
    override func translation(in view: UIView?) -> CGPoint { direction }
    override func location(in view: UIView?) -> CGPoint { CGPoint(x: 20, y: 20) }
}

@MainActor
private final class OriginalDelegate: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool { true }
}
