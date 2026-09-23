import XCTest
@testable import NeoBili

@MainActor
final class DynamicFeedPerformanceTests: XCTestCase {
    func testPaginationUsesIdentityAndOnlyLoadsNearTail() async throws {
        let first = try page(ids: (0..<100).map(String.init))
        var calls = 0
        let model = DynamicFeedModel(source: .following, likeStore: VideoLikeStore()) { _, _, _ in
            calls += 1
            return first
        }
        await model.loadInitial()
        await model.loadMoreIfNeeded(current: first.entries[0])
        XCTAssertEqual(calls, 1)
        // 同一动态的其他字段变化不应影响分页边界判断。
        let changed = try page(ids: ["96"], text: "updated").entries[0]
        await model.loadMoreIfNeeded(current: changed)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(model.entries.count, 100)
    }

    func testFilteredTailCanRequestNextPageAndDeduplicatesIncomingPage() async throws {
        let first = try page(ids: (0..<10).map(String.init))
        let next = try page(ids: ["9", "10", "10", "11"])
        var calls = 0
        let model = DynamicFeedModel(source: .following, likeStore: VideoLikeStore()) { _, _, _ in
            calls += 1
            return calls == 1 ? first : next
        }
        await model.loadInitial()
        // 后九条被用户的筛选条件隐藏，真实可见尾行仍应能触发续页。
        await model.loadMoreIfNeeded(current: first.entries[0], lastVisibleID: "0")
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(model.entries.map(\.id), (0..<12).map(String.init))
    }

    func testRefreshDropsOldIdentityIndexAndAllowsOldIDsInNewPages() async throws {
        let first = try page(ids: ["old"])
        let refreshed = try page(ids: ["new"])
        var calls = 0
        let model = DynamicFeedModel(source: .following, likeStore: VideoLikeStore()) { _, _, _ in
            calls += 1
            return calls == 2 ? refreshed : first
        }
        await model.loadInitial()
        await model.refresh()
        await model.loadMoreIfNeeded(current: first.entries[0], lastVisibleID: "old")
        XCTAssertEqual(calls, 2, "已移除的行不能触发分页")
        await model.loadMoreIfNeeded(current: refreshed.entries[0])
        XCTAssertEqual(model.entries.map(\.id), ["new", "old"])
    }

    func testLeavingViewportDoesNotDiscardInFlightPage() async throws {
        let first = try page(ids: ["first"])
        let next = try page(ids: ["next"])
        var pending: CheckedContinuation<DynamicFeedPage, Never>?
        var calls = 0
        let model = DynamicFeedModel(source: .following, likeStore: VideoLikeStore()) { _, _, _ in
            calls += 1
            if calls == 1 { return first }
            return await withCheckedContinuation { pending = $0 }
        }
        await model.loadInitial()
        let visibleRow = Task { await model.loadMoreIfNeeded(current: first.entries[0]) }
        for _ in 0..<10_000 {
            if pending != nil { break }
            await Task.yield()
        }
        let continuation = try XCTUnwrap(pending)
        visibleRow.cancel()
        continuation.resume(returning: next)
        await visibleRow.value
        XCTAssertEqual(model.entries.map(\.id), ["first", "next"])
        XCTAssertFalse(model.isLoadingMore)
    }

    private func page(ids: [String], text: String = "test") throws -> DynamicFeedPage {
        let items: [[String: Any]] = ids.map {
            ["id_str": $0, "type": "DYNAMIC_TYPE_WORD",
             "modules": ["module_dynamic": ["desc": ["text": text]]]]
        }
        let data = try JSONSerialization.data(withJSONObject: ["has_more": true, "offset": "cursor", "items": items])
        return try JSONDecoder().decode(DynamicFeedPage.self, from: data)
    }
}
