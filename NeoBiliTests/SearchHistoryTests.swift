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

@MainActor
final class SearchViewModelTests: XCTestCase {
    private func item(_ id: String) -> SearchResultItem {
        SearchResultItem(bvid: id, title: id, author: "UP", pic: "", duration: "1:00", play: 0)
    }

    func testPaginationDeduplicatesAndResetAllowsSameIDsAgain() async throws {
        let model = SearchViewModel(searchVideos: { _, page in
            SearchResultPage(result: page == 1 ? [self.item("A"), self.item("A"), self.item("")]
                             : [self.item("A"), self.item("B"), self.item("B")], vVoucher: nil, numPages: 2)
        }, recordHistory: { _ in })
        model.submit(keyword: "first")
        try await waitUntil { !model.isLoading }
        XCTAssertEqual(model.results.map(\.bvid), ["A"])
        await model.loadMore()
        XCTAssertEqual(model.results.map(\.bvid), ["A", "B"])
        XCTAssertFalse(model.hasMore)
        model.submit(keyword: "second")
        try await waitUntil { !model.isLoading }
        XCTAssertEqual(model.results.map(\.bvid), ["A"])
        XCTAssertEqual(model.pageNumber, 1)
    }

    func testResetInvalidatesUncancelledSuggestionResponse() async throws {
        var response: CheckedContinuation<[SearchSuggestion], Error>?
        let model = SearchViewModel(searchSuggestions: { _ in
            try await withCheckedThrowingContinuation { response = $0 }
        }, recordHistory: { _ in })
        model.query = "query"
        let loading = Task { await model.loadSuggestions() }
        try await waitUntil { response != nil }
        // Reset does not change the query: a term equality check alone accepts this stale response.
        model.reset()
        response?.resume(returning: [.init(value: "stale")])
        await loading.value
        XCTAssertTrue(model.suggestions.isEmpty)
    }

    func testSupersededSearchCannotReplaceNewerResults() async throws {
        var oldResponse: CheckedContinuation<SearchResultPage, Error>?
        let model = SearchViewModel(searchVideos: { keyword, _ in
            if keyword == "old" {
                return try await withCheckedThrowingContinuation { oldResponse = $0 }
            }
            return SearchResultPage(result: [self.item("new")], vVoucher: nil)
        }, recordHistory: { _ in })
        model.submit(keyword: "old")
        try await waitUntil { oldResponse != nil }
        model.submit(keyword: "new")
        try await waitUntil { !model.isLoading }
        oldResponse?.resume(returning: SearchResultPage(result: [item("old")], vVoucher: nil))
        await Task.yield()
        XCTAssertEqual(model.results.map(\.bvid), ["new"])
        XCTAssertEqual(model.submittedKeyword, "new")
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw NSError(domain: "SearchViewModelTests.timeout", code: 1)
    }
}
