import SwiftUI
import UIKit
import XCTest
@testable import NeoBili

/// Exercises the actual UIKit moving container with local SwiftUI content.
/// No playback engine, network request, or Simulator is involved.
@MainActor
final class MiniPlayerMotionTests: XCTestCase {
    func testContainerLayoutKeepsOneHostingChildAndDoesNotMoveWhenStoppingIdle() {
        let controller = MiniPlayerContainerController(content: Color.clear)
        let anchor = CGPoint(x: 0, y: 0.4)
        controller.configure(aspectRatio: 16.0 / 9, anchor: anchor, reduceMotion: false,
                             onAnchorChange: { _ in })
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        controller.viewDidLayoutSubviews()
        let originalCenter = controller.host.view.center
        let originalBounds = controller.host.view.bounds
        XCTAssertEqual(controller.children.count, 1)
        XCTAssertTrue(controller.host.parent === controller)
        XCTAssertGreaterThan(originalBounds.width, 0)
        XCTAssertEqual(originalBounds.width / originalBounds.height, 16.0 / 9, accuracy: 0.001)
        controller.stopMotion()
        controller.viewDidLayoutSubviews()
        XCTAssertEqual(controller.host.view.center, originalCenter)
        XCTAssertEqual(controller.host.view.bounds, originalBounds)

        controller.configure(aspectRatio: 9.0 / 16, anchor: anchor, reduceMotion: false,
                             onAnchorChange: { _ in })
        controller.view.layoutIfNeeded()
        controller.viewDidLayoutSubviews()
        XCTAssertEqual(controller.host.view.bounds.width / controller.host.view.bounds.height,
                       9.0 / 16, accuracy: 0.001)
        XCTAssertEqual(controller.children.count, 1)
    }

    func testRealDeviceMiniLayoutPassesBlankAreaTouchesThrough() async throws {
        let content = Color.red
            .overlay { Text("小窗 UIKit 布局").foregroundStyle(.white).font(.caption) }
            .contentShape(Rectangle())
        let controller = MiniPlayerContainerController(content: content)
        controller.configure(aspectRatio: 16.0 / 9, anchor: CGPoint(x: 1, y: 1), reduceMotion: true,
                             onAnchorChange: { _ in })
        let (window, previous) = try present(controller)
        defer { dismiss(window, previous: previous, controller: controller) }
        try await Task.sleep(for: .milliseconds(80))
        controller.view.layoutIfNeeded()
        let root = try XCTUnwrap(controller.view)
        let floating = try XCTUnwrap(controller.host.view)
        XCTAssertGreaterThan(root.bounds.height, 600, "Fixture must use the iPhone's full-size window")
        XCTAssertTrue(root.bounds.contains(floating.frame))
        XCTAssertNil(root.hitTest(CGPoint(x: 2, y: 2), with: nil), "Blank overlay area must leave the underlying list interactive")
        XCTAssertNotNil(root.hitTest(floating.center, with: nil), "The floating content must retain its own hit targets")

        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = "mini-player-real-device-layout-and-passthrough"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testInterruptingSpringPreservesPresentationCenterAndNextDragOrigin() async throws {
        let controller = MiniPlayerContainerController(content: Color.clear.contentShape(Rectangle()))
        controller.configure(aspectRatio: 16.0 / 9, anchor: CGPoint(x: 1, y: 0.6), reduceMotion: false,
                             onAnchorChange: { _ in })
        let (window, previous) = try present(controller)
        let previousAnimationsEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(true)
        defer {
            UIView.setAnimationsEnabled(previousAnimationsEnabled)
            dismiss(window, previous: previous, controller: controller)
        }
        try await Task.sleep(for: .milliseconds(40))
        let bounds = controller.view.safeAreaLayoutGuide.layoutFrame.insetBy(dx: 12, dy: 12)
        let size = controller.host.view.bounds.size
        let travel = bounds.width - size.width
        XCTAssertGreaterThan(travel, 40)
        let gesture = MiniPlayerPanFixture()
        send(gesture, state: .began, translation: .zero, to: controller)
        send(gesture, state: .changed, translation: CGPoint(x: -travel * 0.6, y: 0), to: controller)
        send(gesture, state: .ended, translation: CGPoint(x: -travel * 0.6, y: 0), to: controller)
        try await Task.sleep(for: .milliseconds(60))
        let presentation = try XCTUnwrap(controller.host.view.layer.presentation(),
                                         "An on-screen spring must provide its displayed layer position")
        let visibleCenter = presentation.position
        let targetCenter = controller.host.view.center
        XCTAssertGreaterThan(abs(targetCenter.x - visibleCenter.x), 0.5,
                             "The interruption must occur before the spring settles")
        controller.stopMotion()
        XCTAssertEqual(controller.host.view.center.x, visibleCenter.x, accuracy: 1)
        XCTAssertEqual(controller.host.view.center.y, visibleCenter.y, accuracy: 1)

        let next = MiniPlayerPanFixture()
        send(next, state: .began, translation: .zero, to: controller)
        XCTAssertEqual(controller.host.view.center.x, visibleCenter.x, accuracy: 1)
        let delta = CGPoint(x: 17, y: 9)
        send(next, state: .changed, translation: delta, to: controller)
        let expected = MiniPlayerLayout.clampedCenter(CGPoint(x: visibleCenter.x + delta.x,
                                                             y: visibleCenter.y + delta.y), size: size, in: bounds)
        XCTAssertEqual(controller.host.view.center.x, expected.x, accuracy: 1)
        XCTAssertEqual(controller.host.view.center.y, expected.y, accuracy: 1)
        send(next, state: .cancelled, translation: delta, to: controller)
        controller.stopMotion()
    }

    private func present<Content: View>(_ controller: MiniPlayerContainerController<Content>) throws -> (UIWindow, UIWindow?) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        controller.viewDidLayoutSubviews()
        return (window, previous)
    }

    private func dismiss<Content: View>(_ window: UIWindow, previous: UIWindow?,
                                       controller: MiniPlayerContainerController<Content>) {
        controller.stopMotion()
        window.isHidden = true
        window.rootViewController = nil
        previous?.makeKey()
    }

    private func send<Content: View>(_ gesture: MiniPlayerPanFixture, state: UIGestureRecognizer.State,
                                    translation: CGPoint, to controller: MiniPlayerContainerController<Content>) {
        gesture.fixtureState = state
        gesture.fixtureTranslation = translation
        // The production recognizer targets this Objective-C action. Exercise
        // that same action with controlled samples instead of duplicating motion.
        _ = controller.perform(NSSelectorFromString("panned:"), with: gesture)
    }
}

@MainActor
private final class MiniPlayerPanFixture: UIPanGestureRecognizer {
    var fixtureState: UIGestureRecognizer.State = .possible
    var fixtureTranslation = CGPoint.zero
    override var state: UIGestureRecognizer.State {
        get { fixtureState }
        set { fixtureState = newValue }
    }
    override func translation(in view: UIView?) -> CGPoint { fixtureTranslation }
    override func velocity(in view: UIView?) -> CGPoint { .zero }
}
