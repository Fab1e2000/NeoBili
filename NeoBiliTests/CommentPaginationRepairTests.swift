import XCTest
@testable import NeoBili

@MainActor
final class CommentPaginationRepairTests: XCTestCase {
    func testSubmissionDuringFirstReplyPageDoesNotHideOlderLastReply() async throws {
        let root = try comment(100, count: 21)
        let first = try (1...20).map { try comment($0) }
        let last = try comment(21), submitted = try comment(22)
        var pending: CheckedContinuation<CommentReplyPage, Never>?
        var pages: [Int] = []
        let model = CommentsViewModel(oid: 1, type: 1, fetchReplies: { _, _, _, page in
            pages.append(page)
            if page == 1 { return await withCheckedContinuation { pending = $0 } }
            return CommentReplyPage(page: .init(num: page, size: 20, count: 21), replies: [last])
        })
        let request = Task { await model.loadRepliesIfNeeded(for: root) }
        await waitUntil { pending != nil }
        model.acceptSubmission(submitted, root: root.id)
        pending?.resume(returning: CommentReplyPage(page: .init(num: 1, size: 20, count: 21), replies: first))
        await request.value
        XCTAssertTrue(model.hasMoreReplies(root))
        await model.loadMoreReplies(for: root)
        XCTAssertEqual(pages, [1, 2])
        XCTAssertEqual(model.allReplies(for: root).map(\.id), [22] + Array(1...21))
        XCTAssertFalse(model.hasMoreReplies(root))
        XCTAssertEqual(model.replyCount(for: root), 22)
    }

    func testRootSubmissionDuringInitialRequestDoesNotClosePagination() async throws {
        let first = try (1...20).map { try comment($0) }
        let last = try comment(21), submitted = try comment(22)
        var pending: CheckedContinuation<CommentPage, Never>?
        var pages: [Int] = []
        let model = CommentsViewModel(oid: 1, type: 1, fetchComments: { _, _, page in
            pages.append(page)
            if page == 1 { return await withCheckedContinuation { pending = $0 } }
            return CommentPage(page: .init(num: page, size: 20, count: 21), replies: [last])
        })
        let request = Task { await model.loadInitial() }
        await waitUntil { pending != nil }
        model.acceptSubmission(submitted, root: nil)
        pending?.resume(returning: CommentPage(page: .init(num: 1, size: 20, count: 21), replies: first))
        await request.value
        XCTAssertTrue(model.hasMore)
        await model.loadMoreIfNeeded(current: first[19])
        XCTAssertEqual(pages, [1, 2])
        XCTAssertEqual(model.comments.map(\.id), [22] + Array(1...21))
        XCTAssertFalse(model.hasMore)
    }

    func testSubmissionAlreadyInResponseIsDeduplicatedAndCountsAsServerCoverage() async throws {
        let root = try comment(100, count: 19)
        let first = try (1...20).map { try comment($0) }
        var requests = 0
        let model = CommentsViewModel(oid: 1, type: 1, fetchReplies: { _, _, _, page in
            requests += 1
            return CommentReplyPage(page: .init(num: page, size: 20, count: 20), replies: first)
        })
        model.acceptSubmission(first[19], root: root.id)
        model.acceptSubmission(first[19], root: root.id)
        await model.loadRepliesIfNeeded(for: root)
        await model.loadMoreReplies(for: root)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(model.allReplies(for: root).count, 20)
        XCTAssertEqual(Set(model.allReplies(for: root).map(\.id)).count, 20)
        XCTAssertEqual(model.replyCount(for: root), 20)
    }

    func testRepeatedServerPageStopsWithoutDuplicateRowsOrInfiniteRequests() async throws {
        let root = try comment(100, count: 60)
        let first = try (1...20).map { try comment($0) }
        var pages: [Int] = []
        let model = CommentsViewModel(oid: 1, type: 1, fetchReplies: { _, _, _, page in
            pages.append(page)
            return CommentReplyPage(page: .init(num: page, size: 20, count: 60), replies: first)
        })
        await model.loadRepliesIfNeeded(for: root)
        await model.loadMoreReplies(for: root)
        XCTAssertTrue(model.hasMoreReplies(root))
        await model.loadMoreReplies(for: root)
        await model.loadMoreReplies(for: root)
        XCTAssertEqual(pages, [1, 2, 3])
        XCTAssertEqual(model.allReplies(for: root).count, 20)
        XCTAssertFalse(model.hasMoreReplies(root))
    }

    func testOverlappingPageDoesNotPreventLaterServerPageFromLoading() async throws {
        let root = try comment(100, count: 60)
        let first = try (1...20).map { try comment($0) }
        let final = try (41...60).map { try comment($0) }
        var pages: [Int] = []
        let model = CommentsViewModel(oid: 1, type: 1, fetchReplies: { _, _, _, page in
            pages.append(page)
            return CommentReplyPage(page: .init(num: page, size: 20, count: 60), replies: page < 3 ? first : final)
        })
        await model.loadRepliesIfNeeded(for: root)
        await model.loadMoreReplies(for: root)
        XCTAssertTrue(model.hasMoreReplies(root))
        await model.loadMoreReplies(for: root)
        XCTAssertEqual(pages, [1, 2, 3])
        XCTAssertEqual(model.allReplies(for: root).map(\.id), Array(1...20) + Array(41...60))
        XCTAssertFalse(model.hasMoreReplies(root))
    }

    func testEmptyFinalPageStopsEvenWhenServerCountIsStale() async throws {
        let root = try comment(100, count: 60)
        let first = try (1...20).map { try comment($0) }
        var pages: [Int] = []
        let model = CommentsViewModel(oid: 1, type: 1, fetchReplies: { _, _, _, page in
            pages.append(page)
            return CommentReplyPage(page: .init(num: page, size: 20, count: 60), replies: page == 1 ? first : [])
        })
        await model.loadRepliesIfNeeded(for: root)
        await model.loadMoreReplies(for: root)
        await model.loadMoreReplies(for: root)
        XCTAssertEqual(pages, [1, 2])
        XCTAssertEqual(model.allReplies(for: root).count, 20)
        XCTAssertFalse(model.hasMoreReplies(root))
    }

    func testCancelledAndFailedReplyRequestsRetrySamePageWithoutCountingDiscardedResponse() async throws {
        let root = try comment(100, count: 21)
        let first = try (1...20).map { try comment($0) }
        let last = try comment(21), submitted = try comment(22)
        var pending: CheckedContinuation<CommentReplyPage, Never>?
        var pages: [Int] = []
        let model = CommentsViewModel(oid: 1, type: 1, fetchReplies: { _, _, _, page in
            pages.append(page)
            if pages.count == 1 { return await withCheckedContinuation { pending = $0 } }
            if pages.count == 3 { throw URLError(.timedOut) }
            return CommentReplyPage(page: .init(num: page, size: 20, count: 21), replies: page == 1 ? first : [last])
        })
        let request = Task { await model.loadRepliesIfNeeded(for: root) }
        await waitUntil { pending != nil }
        model.acceptSubmission(submitted, root: root.id)
        request.cancel()
        pending?.resume(returning: CommentReplyPage(page: .init(num: 1, size: 20, count: 21), replies: first))
        await request.value
        XCTAssertNil(model.replyErrors[root.id])
        XCTAssertEqual(model.allReplies(for: root).map(\.id), [22])
        await model.loadRepliesIfNeeded(for: root)
        XCTAssertTrue(model.hasMoreReplies(root))
        await model.loadMoreReplies(for: root)
        XCTAssertNotNil(model.replyErrors[root.id])
        await model.loadMoreReplies(for: root)
        XCTAssertEqual(pages, [1, 1, 2, 2])
        XCTAssertEqual(model.allReplies(for: root).map(\.id), [22] + Array(1...21))
        XCTAssertNil(model.replyErrors[root.id])
        XCTAssertFalse(model.hasMoreReplies(root))
    }

    private func waitUntil(_ ready: () -> Bool) async {
        for _ in 0..<10_000 {
            if ready() { return }
            await Task.yield()
        }
        XCTFail("Request did not reach its controlled suspension point")
    }

    private func comment(_ id: Int, count: Int = 0) throws -> Comment {
        let json = """
        {"rpid":\(id),"ctime":1,"like":0,"rcount":\(count),"member":{"uname":"test","avatar":""},"content":{"message":"test"}}
        """
        return try JSONDecoder().decode(Comment.self, from: Data(json.utf8))
    }
}
