import SwiftUI
import XCTest
@testable import NeoBili

@MainActor
final class AppFontTests: XCTestCase {
    func testStoredStyleDefaultsToStandardAndIgnoresUnknownValues() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "AppFontTests-\(UUID().uuidString)"))
        XCTAssertEqual(AppFontStyle.stored(defaults), .standard)
        defaults.set("unknown", forKey: AppFontStyle.storageKey)
        XCTAssertEqual(AppFontStyle.stored(defaults), .standard)
        defaults.set(AppFontStyle.songti.rawValue, forKey: AppFontStyle.storageKey)
        XCTAssertEqual(AppFontStyle.stored(defaults), .songti)
    }

    func testBundledSongtiCoversLatinAndSimplifiedChineseAtBothWeights() throws {
        for (weight, name) in [(UIFont.Weight.regular, AppFont.regularName), (.medium, AppFont.regularName),
                               (.semibold, AppFont.semiboldName), (.bold, AppFont.semiboldName)] {
            let font = AppFont.uiFont(ofSize: 17, weight: weight, style: .songti)
            XCTAssertEqual(font.fontName, name, "weight \(weight.rawValue)")
            for text in ["Hello 123", "这个发现们"] {
                let ct = CTFontCreateForString(font as CTFont, text as CFString, CFRange(location: 0, length: text.utf16.count))
                XCTAssertEqual(CTFontCopyPostScriptName(ct) as String, name, "\(text) must not fall back")
            }
        }
    }

    func testStandardStyleKeepsSystemMetrics() {
        let traits = UITraitCollection(preferredContentSizeCategory: .large)
        XCTAssertEqual(AppFont.preferred(.subheadline, traits: traits, style: .standard).pointSize,
                       UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traits).pointSize)
        XCTAssertEqual(AppFont.uiFont(ofSize: 15, weight: .semibold, style: .standard),
                       .systemFont(ofSize: 15, weight: .semibold))
    }

    func testSongtiPreferredFontScalesWithContentSize() {
        let small = AppFont.preferred(.body, traits: .init(preferredContentSizeCategory: .small), style: .songti)
        let large = AppFont.preferred(.body, traits: .init(preferredContentSizeCategory: .extraExtraExtraLarge), style: .songti)
        XCTAssertLessThan(small.pointSize, large.pointSize)
        XCTAssertEqual(AppFont.preferred(.headline, traits: nil, style: .songti).fontName, AppFont.semiboldName)
    }
}
