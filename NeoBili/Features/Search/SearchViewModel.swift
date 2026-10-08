import Foundation

@MainActor
@Observable
final class SearchViewModel {
    var query: String = ""
    private(set) var hotSearches: [HotSearchItem] = []
    private(set) var isLoadingHotSearches = false
    private(set) var hotSearchError: String?

    func loadHotSearches() async {
        guard hotSearches.isEmpty, !isLoadingHotSearches else { return }
        isLoadingHotSearches = true
        hotSearchError = nil
        defer { isLoadingHotSearches = false }
        do {
            let payload: HotSearchPayload = try await APIClient.shared.getRaw(
                url: URL(string: "https://s.search.bilibili.com/main/hotword")!,
                additionalHeaders: SearchRequest.headers(keyword: ""))
            guard !Task.isCancelled else { return }
            if payload.code != 0 { throw BiliAPIError.apiError(code: payload.code, message: String(localized: "热搜暂时不可用")) }
            var seen = Set<String>()
            hotSearches = payload.list.filter { !$0.keyword.isEmpty && seen.insert($0.keyword).inserted }
        } catch {
            if !Task.isCancelled { hotSearchError = error.localizedDescription }
        }
    }

    /// 打字过程中的候选词。
    private(set) var suggestions: [SearchSuggestion] = []
    private(set) var results: [SearchResultItem] = []
    /// 每次首批结果发布时递增，让相同关键词的重新搜索也能触发进入动画。
    private(set) var resultsGeneration = 0
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// 已经真正搜过的那个词。为空表示这一页还没搜过东西，页面停在提示状态。
    private(set) var submittedKeyword = ""

    @ObservationIgnored private let searchVideos: (String, Int) async throws -> SearchResultPage
    @ObservationIgnored private let searchSuggestions: (String) async throws -> [SearchSuggestion]
    @ObservationIgnored private let recordHistory: @MainActor (String) -> Void
    @ObservationIgnored private var knownResultIDs = Set<String>()
    @ObservationIgnored private var suggestionRequest = UUID()
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    private(set) var pageNumber = 0
    private(set) var isLoadingMore = false
    private(set) var hasMore = false
    private(set) var loadMoreError: String?

    init(searchVideos: @escaping (String, Int) async throws -> SearchResultPage = { try await BiliAPI.searchVideos(keyword: $0, page: $1) },
         searchSuggestions: @escaping (String) async throws -> [SearchSuggestion] = { try await BiliAPI.searchSuggestions(term: $0) },
         recordHistory: @escaping @MainActor (String) -> Void = { SearchHistory.shared.record($0) }) {
        self.searchVideos = searchVideos
        self.searchSuggestions = searchSuggestions
        self.recordHistory = recordHistory
    }

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
        generation = UUID()
        suggestionRequest = UUID()
        knownResultIDs.removeAll(keepingCapacity: true)
        pageNumber = 0
        isLoadingMore = false
        hasMore = false
        loadMoreError = nil
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
        reset()
        guard !trimmed.isEmpty else { return }
        recordHistory(trimmed)
        submittedKeyword = trimmed
        isLoading = true
        let request = generation
        searchTask = Task {
            defer { if generation == request { isLoading = false } }
            do {
                let page = try await searchVideos(trimmed, 1)
                guard !Task.isCancelled, generation == request else { return }
                append(page, number: 1)
            } catch {
                guard !Task.isCancelled, generation == request else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadMore() async {
        guard !isLoading, !isLoadingMore, hasMore, !submittedKeyword.isEmpty else { return }
        let request = generation
        let keyword = submittedKeyword
        let next = pageNumber + 1
        isLoadingMore = true
        loadMoreError = nil
        defer { if generation == request { isLoadingMore = false } }
        do {
            let page = try await searchVideos(keyword, next)
            guard !Task.isCancelled, generation == request else { return }
            append(page, number: next)
        } catch {
            guard !Task.isCancelled, generation == request else { return }
            loadMoreError = error.localizedDescription
        }
    }

    private func append(_ page: SearchResultPage, number: Int) {
        // Keep the index across pages instead of rescanning the accumulated list.
        let incoming = (page.result ?? []).filter { !$0.bvid.isEmpty && knownResultIDs.insert($0.bvid).inserted }
        results.append(contentsOf: incoming)
        if number == 1 { resultsGeneration += 1 }
        pageNumber = number
        // 有总页数时以接口为准；缺失时在空页或整页重复时停止。
        hasMore = page.numPages.map { number < $0 } ?? !incoming.isEmpty
    }

    /// 取当前输入的联想词。
    ///
    /// 由视图的 `.task(id:)` 驱动：输入变化时上一次的任务会被取消，所以这里
    /// 先睡一小会儿就等于防抖——用户还在连着打字时不会发出请求。
    /// 新输入立即移除旧候选；失败时仍可直接提交当前词。
    func loadSuggestions() async {
        let term = trimmedQuery
        let request = UUID()
        suggestionRequest = request
        suggestions = []
        guard isShowingSuggestions else {
            return
        }

        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }

        do {
            let list = try await searchSuggestions(term)
            guard !Task.isCancelled, suggestionRequest == request,
                  term == trimmedQuery, isShowingSuggestions else { return }
            suggestions = list
        } catch {
            // 静默失败：搜索本身仍然可用。
        }
    }
}

struct HotSearchPayload: Decodable {
    let code: Int
    let list: [HotSearchItem]
}

struct HotSearchItem: Decodable, Identifiable {
    let keyword: String
    let showName: String?
    var id: String { keyword }
    var title: String { showName.flatMap { $0.isEmpty ? nil : $0 } ?? keyword }
    enum CodingKeys: String, CodingKey { case keyword; case showName = "show_name" }
}
