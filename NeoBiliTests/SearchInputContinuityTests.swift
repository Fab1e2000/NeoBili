import SwiftUI
import UIKit
import XCTest
@testable import NeoBili

@MainActor
final class SearchInputContinuityTests: XCTestCase {
    func testFirstComposingCharacterKeepsInputIdentityFocusAndMarkedText() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
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
        XCTAssertTrue(field.becomeFirstResponder())
        field.setMarkedText("n", selectedRange: NSRange(location: 1, length: 0))
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
    var focused = true
}
