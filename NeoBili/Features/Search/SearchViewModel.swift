import Foundation

@MainActor
@Observable
final class SearchViewModel {
    var query: String = ""
    private(set) var results: [SearchResultItem] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var searchTask: Task<Void, Never>?

    func submit() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        searchTask = Task {
            isLoading = true
            errorMessage = nil
            do {
                let page = try await BiliAPI.searchVideos(keyword: trimmed, page: 1)
                if !Task.isCancelled {
                    results = page.result ?? []
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
            isLoading = false
        }
    }
}
