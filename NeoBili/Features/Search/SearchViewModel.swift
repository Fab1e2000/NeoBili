import Foundation

@MainActor
@Observable
final class SearchViewModel {
    var query: String = ""
    /// 打字过程中的候选词。
    private(set) var suggestions: [SearchSuggestion] = []
    private(set) var results: [SearchResultItem] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// 已经真正搜过的那个词。为空表示这一页还没搜过东西，页面停在提示状态。
    private(set) var submittedKeyword = ""

    private var searchTask: Task<Void, Never>?

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 输入内容和上次搜过的词不一样，说明用户正在打新的词，
    /// 这时页面显示联想词而不是上一次的搜索结果。
    var isShowingSuggestions: Bool {
        !trimmedQuery.isEmpty && trimmedQuery != submittedKeyword
    }

    /// 搜过东西了：首页此时把推荐流换成搜索结果。
    var hasSubmittedSearch: Bool {
        !submittedKeyword.isEmpty
    }

    /// 退出搜索（点了「取消」或清空了输入框）：回到什么都没搜过的状态。
    func reset() {
        searchTask?.cancel()
        searchTask = nil
        submittedKeyword = ""
        results = []
        suggestions = []
        errorMessage = nil
        isLoading = false
    }

    /// 开始搜索。传 `keyword` 表示这是点了某个联想词，顺手把输入框也换成它。
    func submit(keyword: String? = nil) {
        if let keyword {
            query = keyword
        }
        let trimmed = trimmedQuery
        searchTask?.cancel()
        suggestions = []

        guard !trimmed.isEmpty else {
            submittedKeyword = ""
            results = []
            errorMessage = nil
            return
        }

        submittedKeyword = trimmed
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
                    results = []
                    errorMessage = error.localizedDescription
                }
            }
            isLoading = false
        }
    }

    /// 取当前输入的联想词。
    ///
    /// 由视图的 `.task(id:)` 驱动：输入变化时上一次的任务会被取消，所以这里
    /// 先睡一小会儿就等于防抖——用户还在连着打字时不会发出请求。
    /// 联想只是锦上添花，失败时保持上一批候选词，不打断用户输入。
    func loadSuggestions() async {
        let term = trimmedQuery
        guard isShowingSuggestions else {
            suggestions = []
            return
        }

        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }

        do {
            let list = try await BiliAPI.searchSuggestions(term: term)
            guard !Task.isCancelled, term == trimmedQuery else { return }
            suggestions = list
        } catch {
            // 静默失败：搜索本身仍然可用。
        }
    }
}
