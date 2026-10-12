import SwiftUI
import UIKit
import XCTest
@testable import NeoBili

@MainActor
final class PlayerGestureInputTests: XCTestCase {
    func testSingleTapHasAnExplicitShortDeadline() {
        let tap = PlayerTapGestureRecognizer()
        var calls: [Bool] = []
        tap.onRecognized = { calls.append($0) }
        tap.began(at: .zero, time: 1)
        tap.ended(at: .zero, time: 1.05)
        tap.expire(at: 1.22)
        XCTAssertTrue(calls.isEmpty)
        tap.expire(at: 1.231)
        XCTAssertEqual(calls, [false], "Single tap fires within 180 ms of release")
        tap.expire(at: 2)
        XCTAssertEqual(calls.count, 1)
    }

    func testDoubleTapFiresOnSecondDownAndSuppressesPendingSingleTap() {
        let tap = PlayerTapGestureRecognizer()
        var calls: [Bool] = []
        tap.onRecognized = { calls.append($0) }
        tap.began(at: .zero, time: 1)
        tap.ended(at: .zero, time: 1.04)
        tap.began(at: CGPoint(x: 4, y: 3), time: 1.14)
        XCTAssertEqual(calls, [true], "Do not wait for the second finger-up")
        tap.ended(at: .zero, time: 1.19)
        tap.expire(at: 2)
        XCTAssertEqual(calls, [true], "Double tap must never also toggle controls")
    }

    func testDraggingHoldingAndCancellationDoNotProduceLateTaps() {
        for action in 0..<3 {
            let tap = PlayerTapGestureRecognizer()
            var calls: [Bool] = []
            tap.onRecognized = { calls.append($0) }
            tap.began(at: .zero, time: 1)
            switch action {
            case 0:
                tap.moved(to: CGPoint(x: 40, y: 0))
                tap.ended(at: CGPoint(x: 40, y: 0), time: 1.1)
            case 1:
                tap.ended(at: .zero, time: 1.4)
            default:
                tap.ended(at: .zero, time: 1.04)
                tap.cancelPendingTap()
            }
            tap.expire(at: 2)
            XCTAssertTrue(calls.isEmpty, "Cancelled, moved or held touches must not reveal controls")
        }
        XCTAssertEqual(PlayerGestureInputView().hold.minimumPressDuration, 0.3)
    }

    func testTransparentInputFillsThePlayerAndDismantlingCancelsInteraction() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        var cancellations = 0
        let host = UIHostingController(rootView: PlayerGestureInput(
            canLongPress: true, onTap: {}, onDoubleTap: {}, onLongPressChanged: { _ in },
            onDrag: { _, _ in }, onCancel: { cancellations += 1 }
        ).frame(width: 320, height: 180))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(100))
        window.layoutIfNeeded()
        func find(_ view: UIView) -> PlayerGestureInputView? {
            if let input = view as? PlayerGestureInputView { return input }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        let input = try XCTUnwrap(find(host.view))
        XCTAssertEqual(input.bounds.width, 320, accuracy: 1)
        XCTAssertEqual(input.bounds.height, 180, accuracy: 1)
        for point in [CGPoint(x: 10, y: 10), CGPoint(x: 160, y: 90), CGPoint(x: 310, y: 170)] {
            XCTAssertTrue(window.hitTest(input.convert(point, to: window), with: nil) === input)
        }
        XCTAssertTrue(input.hold.isEnabled)
        PlayerGestureInput.dismantleUIView(input, coordinator: ())
        XCTAssertEqual(cancellations, 0, "Dismantling must not write SwiftUI state during graph teardown")
        for _ in 0..<100 where cancellations == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(cancellations, 1)
    }
}
