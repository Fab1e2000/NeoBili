import MediaPlayer
import SwiftUI
import XCTest
@testable import NeoBili

@MainActor
final class PlayerGestureVolumeTests: XCTestCase {
    func testVolumeControlOnlyLivesInWindowDuringGestureAndCanBeReused() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        controller.view.addSubview(host)
        let output = PlayerGestureOutput()
        output.view = host
        XCTAssertTrue(host.subviews.isEmpty, "Idle player must not suppress the hardware-key HUD")
        for _ in 0..<3 {
            output.beginVolumeGesture()
            let control = try XCTUnwrap(host.subviews.first as? MPVolumeView)
            XCTAssertTrue(control.window === window)
            output.beginVolumeGesture()
            XCTAssertEqual(host.subviews.count, 1, "Drag updates must reuse the gesture's control")
            output.endVolumeGesture()
            XCTAssertNil(control.window)
            XCTAssertNil(control.superview, "Ending or cancelling restores the hardware-key HUD immediately")
            output.endVolumeGesture()
            XCTAssertTrue(host.subviews.isEmpty)
        }
    }

    func testDismantlingHostRemovesActiveVolumeControl() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        controller.view.addSubview(host)
        let output = PlayerGestureOutput()
        output.view = host
        output.beginVolumeGesture()
        let control = try XCTUnwrap(host.subviews.first as? MPVolumeView)
        PlayerGestureOutputView.dismantleUIView(host, coordinator: output)
        XCTAssertNil(control.window)
        XCTAssertNil(output.view)
        output.beginVolumeGesture()
        XCTAssertTrue(host.subviews.isEmpty, "A dismantled player cannot keep suppressing system feedback")
    }
}
