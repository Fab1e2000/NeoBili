#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation
import Observation

/// 「全部关注」：按关注时间倒序分页读取自己关注的全部 UP 主。
@MainActor
@Observable
final class FollowingAllUpsModel {
    typealias Loader = @Sendable (Int, Int) async throws -> FollowingsPage
    private(set) var ups: [FollowedUp] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var hasMore = true
    private var page = 0
    private let mid: Int
    private let loader: Loader
    private var pageSignatures: Set<Set<Int>> = []

    init(mid: Int, loader: @escaping Loader = { mid, page in
        try await ApplicationServices.live.community.followings(mid: mid, page: page)
    }) {
        self.mid = mid
        self.loader = loader
    }

    func loadInitial() async {
        guard ups.isEmpty, !isLoading else { return }
        await loadMore()
    }

    func loadMoreIfNeeded(current up: FollowedUp) async {
        guard up.mid == ups.last?.mid, errorMessage == nil else { return }
        await loadMore()
    }

    func loadMore() async {
        guard hasMore, !isLoading, !Task.isCancelled else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            // A shifting follow list can overlap page boundaries. Keep scanning
            // duplicate-only pages without requiring the unchanged last cell to reappear.
            while hasMore {
                try Task.checkCancellation()
                let result = try await loader(mid, page + 1)
                try Task.checkCancellation()
                page += 1
                let signature = Set(result.ups.map(\.mid))
                guard !signature.isEmpty, pageSignatures.insert(signature).inserted else {
                    hasMore = false
                    return
                }
                var known = Set(ups.map(\.mid))
                let additions = result.ups.filter { known.insert($0.mid).inserted }
                ups.append(contentsOf: additions)
                hasMore = ups.count < result.total
                if !additions.isEmpty { return }
            }
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            errorMessage = error.localizedDescription
        }
    }
}

