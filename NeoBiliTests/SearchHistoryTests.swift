import XCTest
@testable import NeoBili

@MainActor
final class SearchHistoryTests: XCTestCase {
    func testHistoryDeduplicatesMovesToFrontAndPersistsDeletion() {
        let suite = "SearchHistoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = SearchHistory(defaults: defaults)
        history.record(" Swift ")
        history.record("视频")
        history.record("swift")
        history.record(" \n ")
        XCTAssertEqual(history.keywords, ["swift", "视频"])
        XCTAssertEqual(SearchHistory(defaults: defaults).keywords, history.keywords)
        for index in 0..<40 { history.record("关键词\(index)") }
        XCTAssertEqual(history.keywords.count, 30)
        XCTAssertEqual(history.keywords.first, "关键词39")
        history.clear()
        XCTAssertTrue(SearchHistory(defaults: defaults).keywords.isEmpty)
    }
}
