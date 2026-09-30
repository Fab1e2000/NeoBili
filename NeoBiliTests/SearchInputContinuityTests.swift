import SwiftUI
import UIKit
import XCTest
@testable import NeoBili

@MainActor
final class SearchInputContinuityTests: XCTestCase {
    func testFirstComposingCharacterKeepsInputIdentityFocusAndMarkedText() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive }))
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let model = SearchViewModel()
        let focus = SearchFocusFixture()
        let host = UIHostingController(rootView: NavigationStack {
            SearchPage(viewModel: model, isFocused: Binding(get: { focus.focused }, set: { focus.focused = $0 }), onSubmit: { _ in })
        })
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        func input(_ view: UIView) -> UISearchTextField? {
            if let field = view as? UISearchTextField { return field }
            return view.subviews.compactMap(input).first
        }
        try await Task.sleep(for: .milliseconds(250))
        let field = try XCTUnwrap(input(host.view))
        // This fixture supplies marked text itself. A real third-party keyboard
        // can asynchronously replace that synthetic composition while its XPC
        // extension starts, independently of the search view's identity.
        field.inputView = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 216))
        field.reloadInputViews()
        // Install the synthetic keyboard before requesting focus. Otherwise a
        // cold simulator may still be starting its real keyboard when we mark text.
        focus.focused = true
        XCTAssertTrue(field.becomeFirstResponder())
        var stableFocusSamples = 0
        for _ in 0..<100 {
            window.layoutIfNeeded()
            stableFocusSamples = field.isFirstResponder && focus.focused ? stableFocusSamples + 1 : 0
            if stableFocusSamples == 5 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(stableFocusSamples, 5, "Search input must settle before composition starts")
        field.setMarkedText("n", selectedRange: NSRange(location: 1, length: 0))
        XCTAssertNotNil(field.markedTextRange, "The fixture must establish marked text before switching content")
        model.query = "n"
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(model.isShowingSuggestions)
        XCTAssertTrue(input(host.view) === field, "Suggestions must not replace the search field")
        XCTAssertTrue(field.isFirstResponder)
        XCTAssertTrue(focus.focused)
        XCTAssertNotNil(field.markedTextRange, "Chinese composition must survive the content switch")
        XCTAssertEqual(field.text, "n")
        field.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0))
        model.query = "ni"
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(input(host.view) === field)
        XCTAssertTrue(field.isFirstResponder)
        XCTAssertNotNil(field.markedTextRange)
        field.unmarkText()
        field.text = "你"
        model.query = "你"
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(input(host.view) === field)
        XCTAssertTrue(field.isFirstResponder)
        XCTAssertEqual(field.text, "你")
    }
}

@MainActor @Observable private final class SearchFocusFixture {
    var focused = false
}
