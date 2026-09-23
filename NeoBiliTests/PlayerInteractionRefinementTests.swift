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
