import Foundation
import NeoBiliDomain

@MainActor @Observable
final class SpaceCollectionsModel {
    private let mid: Int
    private let services: ApplicationServices
    let list = SpaceCollectionPagination<SpaceCollectionSummary>()

    var collections: [SpaceCollectionSummary] { list.items }

    init(mid: Int, services: ApplicationServices) {
        self.mid = mid
        self.services = services
    }

    func loadIfNeeded() async {
        guard !list.hasLoadedCurrentOrder else { return }
        await reload()
    }

    func reload() async { await list.reload(fetchPage) }

    func stageRefresh() async -> Bool { await list.stageRefresh(fetchPage) }
    func commitRefresh() { list.commitRefresh() }
    func discardRefresh() { list.discardRefresh() }

    func loadMoreIfNeeded(current: SpaceCollectionSummary) async {
        guard list.paginationError == nil,
              collections.suffix(5).contains(where: { $0.id == current.id }) else { return }
        await loadMore()
    }

    func loadMore() async { await list.loadMore(fetchPage) }

    private func fetchPage(_ page: Int, loadedCount: Int) async throws -> SpaceCollectionPagination<SpaceCollectionSummary>.Page {
        let result = try await services.community.spaceCollections(mid: mid, page: page)
        return .init(items: result.collections, rawItemCount: result.rawItemCount, number: result.pageNumber,
                     hasMore: result.hasMore(after: loadedCount + result.rawItemCount, requestedPage: page))
    }
}

/// 合集目录和分集共用分页及暂存刷新。游标按服务端页推进，显示数据按行标识去重。
@MainActor @Observable
final class SpaceCollectionPagination<Item: Identifiable & Sendable> {
    struct Page: Sendable {
        let items: [Item]
        let rawItemCount: Int
        let number: Int?
        let hasMore: Bool
    }

    typealias FetchPage = @MainActor (Int, Int) async throws -> Page

    private(set) var items: [Item] = []
    private(set) var generation = 0
    var hasLoadedCurrentOrder: Bool { page > 0 }
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var hasMore = false
    private(set) var errorMessage: String?
    private(set) var paginationError: String?
    var canLoadMore: Bool { hasMore && !isLoading && !isLoadingMore && stagedPage == nil }

    private var page = 0
    @ObservationIgnored private var loadedCount = 0
    @ObservationIgnored private var requestID = UUID()
    private var stagedPage: Page?
    @ObservationIgnored private var activeFetch: Task<Page, Error>?
    @ObservationIgnored private var order: ((Item, Item) -> Bool)?

    init(order: ((Item, Item) -> Bool)? = nil) {
        self.order = order
    }

    func reload(_ fetch: @escaping FetchPage) async {
        _ = await loadFirstPage(staged: false, fetch)
    }

    func stageRefresh(_ fetch: @escaping FetchPage) async -> Bool {
        await loadFirstPage(staged: true, fetch)
    }

    private func loadFirstPage(staged: Bool, _ fetch: @escaping FetchPage) async -> Bool {
        guard !isLoading, stagedPage == nil, !Task.isCancelled else { return false }
        let request = UUID()
        requestID = request
        activeFetch?.cancel()
        isLoadingMore = false
        isLoading = true
        errorMessage = nil
        defer {
            if requestID == request {
                isLoading = false
                activeFetch = nil
            }
        }
        do {
            let result = try await fetchPage(1, loadedCount: 0, using: fetch)
            guard requestID == request, !Task.isCancelled else { return false }
            stagedPage = result
            if !staged { commitRefresh() }
            return true
        } catch {
            guard requestID == request, !Task.isCancelled, !error.isCancellation else { return false }
            errorMessage = error.loadFailureDescription
            return false
        }
    }

    func commitRefresh() {
        guard let stagedPage else { return }
        items = []
        loadedCount = 0
        page = 0
        append(stagedPage)
        paginationError = nil
        generation += 1
        self.stagedPage = nil
    }

    func discardRefresh() {
        stagedPage = nil
        if isLoading {
            requestID = UUID()
            activeFetch?.cancel()
            activeFetch = nil
            isLoading = false
        }
    }

    func resetForNewOrder(_ order: @escaping (Item, Item) -> Bool) {
        discardRefresh()
        requestID = UUID()
        activeFetch?.cancel()
        activeFetch = nil
        isLoadingMore = false
        items = []
        self.order = order
        page = 0
        loadedCount = 0
        hasMore = false
        errorMessage = nil
        paginationError = nil
    }

    func loadMore(_ fetch: @escaping FetchPage) async {
        guard canLoadMore, !Task.isCancelled else { return }
        let request = requestID
        isLoadingMore = true
        paginationError = nil
        defer {
            if requestID == request {
                isLoadingMore = false
                activeFetch = nil
            }
        }

        // 整页被跳过或只有重复项时，继续请求下一页，因为没有新行能触发翻页。
        let previousCount = items.count
        do {
            repeat {
                let nextPage = page + 1
                let result = try await fetchPage(nextPage, loadedCount: loadedCount, using: fetch)
                guard requestID == request, !Task.isCancelled else { return }
                if let reportedPage = result.number, reportedPage > 0, reportedPage != nextPage {
                    // 服务端重复返回旧页时不再推进本地游标。
                    hasMore = false
                    return
                }
                append(result)
            } while hasMore && items.count == previousCount
        } catch {
            guard requestID == request, !Task.isCancelled, !error.isCancellation else { return }
            paginationError = error.loadFailureDescription
        }
    }

    private func fetchPage(_ page: Int, loadedCount: Int, using fetch: @escaping FetchPage) async throws -> Page {
        let task = Task {
            try Task.checkCancellation()
            return try await fetch(page, loadedCount)
        }
        activeFetch = task
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func append(_ result: Page) {
        var seen = Set(items.map(\.id))
        items.append(contentsOf: result.items.filter { seen.insert($0.id).inserted })
        if let order { items.sort(by: order) }
        page += 1
        loadedCount += result.rawItemCount
        hasMore = result.hasMore && result.rawItemCount > 0
    }
}
