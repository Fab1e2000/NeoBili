#if canImport(NeoBiliDomain)
@testable import NeoBiliDomain
#endif
import XCTest
import Synchronization
@testable import NeoBili

@MainActor
final class CommentFeatureTests: XCTestCase {
    func testAuthorUIDAcceptsNumbersAndStringsButNeverInfersFromName() throws {
        for uid: Any in [42, "42"] {
            let value = try fixture(1, uid: uid)
            XCTAssertEqual(value.authorID, 42)
            XCTAssertTrue(value.isAuthored(by: 42))
            XCTAssertFalse(value.isAuthored(by: 43))
        }
        for uid: Any in [NSNull(), "invalid", -1, 0, 4.5, true] {
            let value = try fixture(1, uid: uid)
            XCTAssertNil(value.authorID)
            XCTAssertFalse(value.isAuthored(by: 42))
        }
        let missing = try fixture(1)
        XCTAssertNil(missing.authorID)
        let model = CommentsViewModel(oid: 1, type: 1, uploaderID: 42)
        XCTAssertTrue(model.isUploader(try fixture(1, uid: 42)))
        XCTAssertFalse(model.isUploader(try fixture(2, uid: 43))) // Same display name.
        XCTAssertFalse(model.isUploader(missing))
    }

    func testOptionalPinAndUPFieldsAreLenientAndPinsDeduplicate() throws {
        let pin = object(1, uid: "42")
        var response: [String: Any] = ["page": ["num": 1, "size": 20, "count": 1], "replies": [pin],
            "upper": ["mid": "42", "top": pin], "top": ["upper": pin, "admin": false],
            "top_replies": [false, pin, ["broken": 1]]]
        let page = try decode(CommentPage.self, response)
        XCTAssertEqual(page.uploaderID, 42)
        XCTAssertEqual(page.pinnedReplies.map(\.id), [1])
        response["upper"] = "unknown"
        response["top"] = []
        response["top_replies"] = false
        let malformed = try decode(CommentPage.self, response)
        XCTAssertNil(malformed.uploaderID)
        XCTAssertTrue(malformed.pinnedReplies.isEmpty)
        XCTAssertEqual(malformed.replies?.count, 1)
        var value = object(2)
        value["up_action"] = ["like": true, "reply": true]
        let both = try decode(Comment.self, value)
        XCTAssertTrue(both.upAction?.like == true && both.upAction?.reply == true)
        value["up_action"] = ["like": "yes", "reply": true]
        let partial = try decode(Comment.self, value)
        XCTAssertFalse(partial.upAction?.like == true)
        XCTAssertTrue(partial.upAction?.reply == true)
        value["up_action"] = 7
        XCTAssertNil(try decode(Comment.self, value).upAction)
        let info = try decode(CommentPageInfo.self, ["num": 1, "size": 20, "count": 3, "acount": "invalid"])
        XCTAssertNil(info.allCount)
        XCTAssertEqual(info.count, 3)
    }

    func testPinsStayFirstInBothSortsWithoutChangingServerPagination() async throws {
        let pin = try fixture(99, uid: 42), a = try fixture(1), b = try fixture(2)
        var calls: [(Int, CommentSort)] = []
        let model = CommentsViewModel(oid: 1, type: 1, fetchComments: { _, _, number, sort in
            calls.append((number, sort))
            return .init(page: .init(num: number, size: 1, count: 2), replies: [number == 1 ? a : b],
                         uploaderID: 42, pinnedReplies: [pin, pin])
        })
        await model.loadInitial()
        XCTAssertEqual(model.comments.map(\.id), [99, 1])
        XCTAssertTrue(model.hasMore)
        await model.loadMoreIfNeeded(current: a)
        XCTAssertEqual(model.comments.map(\.id), [99, 1, 2])
        XCTAssertFalse(model.hasMore)
        await model.changeSort(to: .latest)
        XCTAssertEqual(model.comments.map(\.id), [99, 1])
        XCTAssertEqual(model.sort, .latest)
        XCTAssertEqual(calls.map(\.0), [1, 2, 1])
        XCTAssertEqual(calls.map(\.1), [.hot, .hot, .latest])
        XCTAssertTrue(model.isUploader(pin))
    }

    func testLatePageCannotOverwriteSuccessfulSort() async throws {
        let a = try fixture(1), old = try fixture(2), fresh = try fixture(3)
        var pending: CheckedContinuation<CommentPage, Never>?
        let model = CommentsViewModel(oid: 1, type: 1, fetchComments: { _, _, number, sort in
            if sort == .latest { return self.page([fresh], count: 1) }
            if number == 1 { return self.page([a], count: 2, size: 1) }
            return await withCheckedContinuation { pending = $0 }
        })
        await model.loadInitial()
        let pagination = Task { await model.loadMoreIfNeeded(current: a) }
        await waitUntil { pending != nil }
        await model.changeSort(to: .latest)
        pending?.resume(returning: page([old], count: 2, size: 1, number: 2))
        await pagination.value
        XCTAssertEqual(model.comments.map(\.id), [3])
        XCTAssertEqual(model.sort, .latest)
        XCTAssertEqual(model.scrollRevision, 1)
        XCTAssertFalse(model.isLoadingMore)
    }

    func testNewestReloadWinsAndFailurePreservesSortListAndDraft() async throws {
        let a = try fixture(1), stale = try fixture(2), fresh = try fixture(3)
        var pending: CheckedContinuation<CommentPage, Never>?
        var fails = false
        var calls = 0
        let model = CommentsViewModel(oid: 1, type: 1, fetchComments: { _, _, _, sort in
            calls += 1
            if fails { throw URLError(.timedOut) }
            if sort == .latest { return await withCheckedContinuation { pending = $0 } }
            return self.page([calls == 1 ? a : fresh], count: 1)
        })
        await model.loadInitial()
        model.commentDraft(root: 0).text = "keep draft"
        let change = Task { await model.changeSort(to: .latest) }
        await waitUntil { pending != nil }
        await model.refresh()
        pending?.resume(returning: page([stale], count: 1))
        await change.value
        XCTAssertEqual(model.comments.map(\.id), [3])
        XCTAssertEqual(model.sort, .hot)
        fails = true
        await model.changeSort(to: .latest)
        XCTAssertEqual(model.sort, .hot)
        XCTAssertEqual(model.comments.map(\.id), [3])
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.commentDraft(root: 0).text, "keep draft")
        XCTAssertEqual(model.scrollRevision, 0)
    }

    func testFailedSortRetryRequestsIntendedSortAndFirstPage() async throws {
        let a = try fixture(1)
        var fail = true
        var calls: [(Int, CommentSort)] = []
        let model = CommentsViewModel(oid: 1, type: 1, fetchComments: { _, _, number, sort in
            calls.append((number, sort))
            if sort == .latest && fail { throw URLError(.timedOut) }
            return self.page([a], count: 1)
        })
        await model.loadInitial()
        await model.changeSort(to: .latest)
        fail = false
        await model.retry()
        XCTAssertEqual(calls.map(\.0), [1, 1, 1])
        XCTAssertEqual(calls.map(\.1), [.hot, .latest, .latest])
        XCTAssertEqual(model.sort, .latest)
        XCTAssertNil(model.errorMessage)
    }

    func testRefreshPreservesConcurrentConfirmedSubmissionAndDoesNotDuplicateIt() async throws {
        let a = try fixture(1), new = try fixture(2, uid: 42)
        var pending: CheckedContinuation<CommentPage, Never>?
        var calls = 0
        let model = CommentsViewModel(oid: 1, type: 1, fetchComments: { _, _, _, _ in
            calls += 1
            if calls == 2 { return await withCheckedContinuation { pending = $0 } }
            return self.page(calls == 1 ? [a] : [new, a], count: calls == 1 ? 1 : 2)
        })
        await model.loadInitial()
        let refresh = Task { await model.refresh() }
        await waitUntil { pending != nil }
        model.acceptSubmission(new, root: nil)
        pending?.resume(returning: page([a], count: 1))
        await refresh.value
        XCTAssertEqual(model.comments.map(\.id), [2, 1])
        XCTAssertEqual(model.totalCount, 2)
        await model.refresh()
        XCTAssertEqual(model.comments.map(\.id), [2, 1])
        XCTAssertEqual(model.totalCount, 2)
    }

    func testReplySubmissionThenMainRefreshDoesNotDoubleCountOutsidePreview() async throws {
        let original = try fixture(10, count: 8, replies: [object(11)])
        let refreshed = try fixture(10, count: 9, replies: [object(11)])
        let mine = try fixture(12, uid: 42)
        var calls = 0
        let model = CommentsViewModel(oid: 1, type: 1, fetchComments: { _, _, _, _ in
            calls += 1
            return self.page([calls == 1 ? original : refreshed], count: 1)
        })
        await model.loadInitial()
        model.acceptSubmission(mine, root: 10)
        XCTAssertEqual(model.replyCount(for: original), 9)
        await model.refresh()
        XCTAssertEqual(model.replyCount(for: original), 9)
        XCTAssertEqual(model.replies(for: original).map(\.id), [12, 11])
    }

    func testRefreshRepliesIsolatesOldPaginationAndKeepsDraftOnFailure() async throws {
        let root = try fixture(10, count: 3), a = try fixture(1), b = try fixture(2)
        var pending: CheckedContinuation<CommentReplyPage, Never>?
        var firstCalls = 0
        var fail = false
        let model = CommentsViewModel(oid: 1, type: 1, fetchReplies: { _, _, _, number in
            if fail { throw URLError(.timedOut) }
            if number == 2 { return await withCheckedContinuation { pending = $0 } }
            firstCalls += 1
            return .init(page: .init(num: 1, size: 1, count: 3), replies: [firstCalls == 1 ? a : b])
        })
        await model.loadRepliesIfNeeded(for: root)
        let pagination = Task { await model.loadMoreReplies(for: root) }
        await waitUntil { pending != nil }
        model.commentDraft(root: root.id).text = "reply draft"
        await model.refreshReplies(for: root)
        pending?.resume(returning: .init(page: .init(num: 2, size: 1, count: 3), replies: [a]))
        await pagination.value
        XCTAssertEqual(model.allReplies(for: root).map(\.id), [2])
        fail = true
        await model.refreshReplies(for: root)
        XCTAssertEqual(model.allReplies(for: root).map(\.id), [2])
        XCTAssertEqual(model.commentDraft(root: root.id).text, "reply draft")
        XCTAssertNotNil(model.replyErrors[root.id])
    }

    func testDeleteReplySynchronizesPreviewThreadCountAndLateResponses() async throws {
        let mine = try fixture(11, uid: 42), other = try fixture(12, uid: 7)
        let root = try fixture(10, count: 2, replies: [object(11, uid: 42), object(12, uid: 7)])
        let session = TestCommentSession()
        var pending: CheckedContinuation<CommentReplyPage, Never>?
        let model = CommentsViewModel(oid: 1, type: 1, services: services(session), fetchReplies: { _, _, _, _ in
            await withCheckedContinuation { pending = $0 }
        }, fetchComments: { _, _, _, _ in self.page([root], count: 1) })
        await model.loadInitial()
        let request = Task { await model.loadRepliesIfNeeded(for: root) }
        await waitUntil { pending != nil }
        let target = try XCTUnwrap(model.deletion(for: mine, root: root, accountID: 42, isLoggedIn: true))
        await model.delete(target, accountID: 42, isLoggedIn: true)
        XCTAssertEqual(model.replies(for: root).map(\.id), [12])
        XCTAssertEqual(model.replyCount(for: root), 1)
        pending?.resume(returning: .init(page: .init(num: 1, size: 20, count: 2), replies: [mine, other]))
        await request.value
        XCTAssertEqual(model.allReplies(for: root).map(\.id), [12])
        XCTAssertEqual(model.replyCount(for: root), 1)
        XCTAssertEqual(model.totalCount, 1)
    }

    func testDeleteRootRemovesPinAndThreadAndLateRefreshCannotRestoreIt() async throws {
        let root = try fixture(1, uid: 42, count: 1, replies: [object(11)])
        let session = TestCommentSession()
        var pending: CheckedContinuation<CommentPage, Never>?
        var calls = 0
        let model = CommentsViewModel(oid: 1, type: 1, services: services(session), fetchComments: { _, _, _, _ in
            calls += 1
            if calls == 2 { return await withCheckedContinuation { pending = $0 } }
            return .init(page: .init(num: 1, size: 20, count: 1), replies: [root], pinnedReplies: [root])
        })
        await model.loadInitial()
        let refresh = Task { await model.refresh() }
        await waitUntil { pending != nil }
        model.commentDraft(root: 0).text = "draft"
        model.commentDraft(root: 0).target = .init(root: 1, parent: 1, name: "same")
        await model.delete(try XCTUnwrap(model.deletion(for: root, root: nil, accountID: 42, isLoggedIn: true)), accountID: 42, isLoggedIn: true)
        pending?.resume(returning: .init(page: .init(num: 1, size: 20, count: 1), replies: [root], pinnedReplies: [root]))
        await refresh.value
        XCTAssertTrue(model.comments.isEmpty)
        XCTAssertTrue(model.pinnedIDs.isEmpty)
        XCTAssertTrue(model.allReplies(for: root).isEmpty)
        XCTAssertTrue(model.deletedIDs.contains(root.id))
        XCTAssertEqual(model.totalCount, 0)
        XCTAssertEqual(model.commentDraft(root: 0).text, "draft")
        XCTAssertNil(model.commentDraft(root: 0).target)
    }

    func testDeleteFailureKeepsContentAndOwnershipRequiresExactUID() async throws {
        let root = try fixture(1, uid: 42)
        let session = TestCommentSession()
        var service = services(session)
        service.comment.deleteCommentOperation = { _, _, _, _ in throw URLError(.timedOut) }
        let model = CommentsViewModel(oid: 1, type: 1, services: service,
            fetchComments: { _, _, _, _ in self.page([root], count: 1) })
        await model.loadInitial()
        XCTAssertNil(model.deletion(for: root, root: nil, accountID: 7, isLoggedIn: true))
        XCTAssertNil(model.deletion(for: root, root: nil, accountID: 42, isLoggedIn: false))
        XCTAssertNil(model.deletion(for: try fixture(2), root: nil, accountID: 42, isLoggedIn: true))
        let target = try XCTUnwrap(model.deletion(for: root, root: nil, accountID: 42, isLoggedIn: true))
        await model.delete(target, accountID: 42, isLoggedIn: true)
        XCTAssertEqual(model.comments.map(\.id), [1])
        XCTAssertFalse(model.deletedIDs.contains(1))
        XCTAssertTrue(model.deletingIDs.isEmpty)
        XCTAssertNotNil(model.actionMessage)
    }

    func testAggregateCountTracksChildAndRootDeletionWithoutChangingPagingCount() async throws {
        let root = try fixture(1, uid: 42, count: 2, replies: [object(11, uid: 42), object(12)])
        let child = try fixture(11, uid: 42)
        let session = TestCommentSession()
        var pending: CheckedContinuation<CommentPage, Never>?
        var calls = 0
        let response = CommentPage(page: .init(num: 1, size: 20, count: 1, allCount: 3), replies: [root])
        let model = CommentsViewModel(oid: 1, type: 1, services: services(session), fetchComments: { _, _, _, _ in
            calls += 1
            if calls == 2 { return await withCheckedContinuation { pending = $0 } }
            return response
        })
        await model.loadInitial()
        XCTAssertEqual(model.displayCount, 3)
        let refresh = Task { await model.refresh() }
        await waitUntil { pending != nil }
        await model.delete(try XCTUnwrap(model.deletion(for: child, root: root, accountID: 42, isLoggedIn: true)), accountID: 42, isLoggedIn: true)
        XCTAssertEqual(model.displayCount, 2)
        XCTAssertEqual(model.totalCount, 1)
        await model.delete(try XCTUnwrap(model.deletion(for: root, root: nil, accountID: 42, isLoggedIn: true)), accountID: 42, isLoggedIn: true)
        XCTAssertEqual(model.displayCount, 0)
        XCTAssertEqual(model.totalCount, 0)
        pending?.resume(returning: response)
        await refresh.value
        XCTAssertEqual(model.displayCount, 0)
    }

    func testDeletionBindsSessionPreventsDuplicatesAndIgnoresLateAccountResponse() async throws {
        let mine = try fixture(1, uid: 42)
        let session = TestCommentSession(), writer = ControlledCommentDeletion()
        var service = services(session)
        service.comment.deleteCommentOperation = { _, _, _, id in try await writer.write(session: id) }
        let model = CommentsViewModel(oid: 1, type: 1, services: service,
            fetchComments: { _, _, _, _ in self.page([mine], count: 1) })
        await model.loadInitial()
        let old = try XCTUnwrap(model.deletion(for: mine, root: nil, accountID: 42, isLoggedIn: true))
        session.rotate()
        await model.delete(old, accountID: 42, isLoggedIn: true)
        let oldCalls = await writer.calls
        XCTAssertTrue(oldCalls.isEmpty)
        let target = try XCTUnwrap(model.deletion(for: mine, root: nil, accountID: 42, isLoggedIn: true))
        let task = Task { await model.delete(target, accountID: 42, isLoggedIn: true) }
        for _ in 0..<10_000 { if await writer.isWaiting { break }; await Task.yield() }
        XCTAssertTrue(model.deletingIDs.contains(1))
        await model.delete(target, accountID: 42, isLoggedIn: true)
        let calls = await writer.calls
        XCTAssertEqual(calls, [target.sessionID])
        session.rotate()
        await writer.finish()
        await task.value
        XCTAssertEqual(model.comments.map(\.id), [1])
        XCTAssertNil(model.actionMessage)
    }

    private func services(_ session: TestCommentSession) -> ApplicationServices {
        var services = ApplicationServices(session: .init(currentID: { session.id }, homeAccount: { .init(accountID: 42, hasAppCredential: false) }))
        services.comment.deleteCommentOperation = { _, _, _, _ in }
        return services
    }
    private func page(_ comments: [Comment], count: Int, size: Int = 20, number: Int = 1) -> CommentPage {
        .init(page: .init(num: number, size: size, count: count), replies: comments)
    }
    private func object(_ id: Int, uid: Any? = nil, count: Int = 0, replies: [[String: Any]] = []) -> [String: Any] {
        var member: [String: Any] = ["uname": "same", "avatar": ""]
        if let uid { member["mid"] = uid }
        return ["rpid": id, "ctime": 1, "like": 1, "rcount": count, "member": member,
                "content": ["message": "完整正文 [doge] https://example.invalid/original"], "replies": replies]
    }
    private func fixture(_ id: Int, uid: Any? = nil, count: Int = 0, replies: [[String: Any]] = []) throws -> Comment {
        try decode(Comment.self, object(id, uid: uid, count: count, replies: replies))
    }
    private func decode<T: Decodable>(_ type: T.Type, _ object: [String: Any]) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
    }
    private func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<10_000 { if predicate() { return }; await Task.yield() }
        XCTFail("Controlled request did not start")
    }
}

private final class TestCommentSession: Sendable {
    private let storage = Mutex(UUID())
    var id: UUID { storage.withLock { $0 } }
    func rotate() { storage.withLock { $0 = UUID() } }
}
private actor ControlledCommentDeletion {
    var calls: [UUID] = []
    private var continuation: CheckedContinuation<Void, Error>?
    var isWaiting: Bool { continuation != nil }
    func write(session: UUID) async throws {
        calls.append(session)
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func finish() { continuation?.resume(); continuation = nil }
}
