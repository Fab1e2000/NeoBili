import Foundation

/// Search operations available to application state and views.
/// Values can be replaced per model or view hierarchy without changing global state.
public struct SearchService: Sendable {
    public var hotSearches: @Sendable () async throws -> [HotSearchItem] = { throw ServiceError.unconfigured("Search.hotSearches") }

    public var searchVideosOperation: @Sendable (String, Int) async throws -> SearchResultPage = { _, _ in throw ServiceError.unconfigured("Search.searchVideos") }
    public var searchSuggestionsOperation: @Sendable (String) async throws -> [SearchSuggestion] = { _ in throw ServiceError.unconfigured("Search.searchSuggestions") }

    public func searchVideos(keyword: String, page: Int) async throws -> SearchResultPage {
        try await searchVideosOperation(keyword, page)
    }

    public func searchSuggestions(term: String) async throws -> [SearchSuggestion] {
        try await searchSuggestionsOperation(term)
    }

    public init(
        hotSearches: @escaping @Sendable () async throws -> [HotSearchItem] = { throw ServiceError.unconfigured("Search.hotSearches") },
        searchVideosOperation: @escaping @Sendable (String, Int) async throws -> SearchResultPage = { _, _ in throw ServiceError.unconfigured("Search.searchVideos") },
        searchSuggestionsOperation: @escaping @Sendable (String) async throws -> [SearchSuggestion] = { _ in throw ServiceError.unconfigured("Search.searchSuggestions") }
    ) {
        self.hotSearches = hotSearches
        self.searchVideosOperation = searchVideosOperation
        self.searchSuggestionsOperation = searchSuggestionsOperation
    }
}
