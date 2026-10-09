import Foundation

/// Search operations available to application state and views.
/// Values can be replaced per model or view hierarchy without changing global state.
struct SearchService: Sendable {
    var hotSearches: @Sendable () async throws -> [HotSearchItem] = { throw ServiceError.unconfigured("Search.hotSearches") }

    var searchVideosOperation: @Sendable (String, Int) async throws -> SearchResultPage = { _, _ in throw ServiceError.unconfigured("Search.searchVideos") }
    var searchSuggestionsOperation: @Sendable (String) async throws -> [SearchSuggestion] = { _ in throw ServiceError.unconfigured("Search.searchSuggestions") }

    func searchVideos(keyword: String, page: Int) async throws -> SearchResultPage {
        try await searchVideosOperation(keyword, page)
    }

    func searchSuggestions(term: String) async throws -> [SearchSuggestion] {
        try await searchSuggestionsOperation(term)
    }
}
