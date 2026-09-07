import XCTest
@testable import NeoBili

/// 所有请求与凭据均为内存假数据；允许在用户真机运行，不读写真实账号。
@MainActor
final class AuditRegressionTests: XCTestCase {
    private struct Row: Identifiable { let id: Int }

    func testConcurrentRemovalUsesIdentityAfterIndicesShift() {
        let state = ListRemovalState<Int>()
        var rows = [Row(id: 1), Row(id: 2)]
        XCTAssertTrue(state.begin(1))
        XCTAssertTrue(state.begin(2))
        XCTAssertFalse(state.begin(2), "重复点击不能发出第二次删除")
        state.hide(1)
        state.hide(2)
        state.remove(1, from: &rows)
        state.remove(2, from: &rows)
        XCTAssertTrue(rows.isEmpty, "第二次删除不能再用旧下标 1")
        state.finish(1)
        state.finish(2)
        XCTAssertTrue(state.hiddenIDs.isEmpty)
    }

    func testRemovalHandlesRefreshAndDeduplicatesRollback() {
        let state = ListRemovalState<Int>()
        var rows = [Row(id: 1), Row(id: 2)]
        let snapshot = state.revision
        XCTAssertTrue(state.begin(2))
        XCTAssertNotEqual(snapshot, state.revision)
        rows = [Row(id: 2), Row(id: 3)] // 动画期间刷新/排序
        let index = state.remove(2, from: &rows)
        XCTAssertEqual(rows.map(\.id), [3])
        rows.insert(Row(id: 2), at: 0) // 失败前刷新已经恢复了同 ID
        state.restore(Row(id: 2), at: index ?? 0, in: &rows)
        XCTAssertEqual(rows.map(\.id), [2, 3])
        rows = []
        XCTAssertNil(state.remove(2, from: &rows))
        state.restore(Row(id: 2), at: 99, in: &rows)
        XCTAssertEqual(rows.map(\.id), [2])
    }

    func testCommentRetryKeepsFirstPageAndRetriesFailedPage() async throws {
        let first = try comment(1), second = try comment(2)
        var requests: [Int] = []
        let model = CommentsViewModel(oid: 1, type: 1, fetchComments: { _, _, page in
            requests.append(page)
            if requests.count == 2 { throw URLError(.timedOut) }
            return CommentPage(page: CommentPageInfo(num: page, size: 1, count: 2),
                               replies: page == 1 ? [first] : [second])
        })
        await model.loadInitial()
        await model.loadMoreIfNeeded(current: first)
        XCTAssertEqual(model.comments.map(\.id), [1])
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.hasMore)
        await model.retry()
        XCTAssertEqual(requests, [1, 2, 2])
        XCTAssertEqual(model.comments.map(\.id), [1, 2])
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.hasMore)
    }

    func testCancelledCommentRequestCanBeLoadedAgain() async throws {
        let first = try comment(1)
        var calls = 0
        let model = CommentsViewModel(oid: 1, type: 1, fetchComments: { _, _, page in
            calls += 1
            if calls == 1 { throw URLError(.cancelled) }
            return CommentPage(page: CommentPageInfo(num: page, size: 1, count: 1), replies: [first])
        })
        await model.loadInitial()
        XCTAssertNil(model.errorMessage)
        await model.loadInitial()
        XCTAssertEqual(model.comments.map(\.id), [1])
    }

    func testOfflineSessionKeepsCredentialsAndRecoversOnRetry() async throws {
        let defaults = try temporaryDefaults()
        var online = false
        let payload = try profile()
        let client = AccountSessionClient(
            credentials: { AccountCredentialsSnapshot(hasCredentials: true, accountID: 42) },
            save: { _, _ in }, clear: {},
            profile: { if !online { throw URLError(.notConnectedToInternet) }; return payload }
        )
        let account = AccountStore(client: client, defaults: defaults, likeStore: VideoLikeStore(), monitorNetwork: false)
        await account.restoreSessionIfNeeded()
        XCTAssertTrue(account.isLoggedIn)
        XCTAssertFalse(account.isRestoringSession)
        XCTAssertNotNil(account.sessionError)
        online = true
        await account.retrySessionIfNeeded()
        XCTAssertEqual(account.profile?.mid, 42)
        XCTAssertNil(account.sessionError)
        online = false
        let restored = AccountStore(client: client, defaults: defaults, likeStore: VideoLikeStore(), monitorNetwork: false)
        await restored.restoreSessionIfNeeded()
        XCTAssertEqual(restored.profile?.mid, 42, "同账号可使用缓存资料离线启动")
    }

    func testLateProfileResponseCannotLogBackInAfterLogout() async throws {
        let pending = Deferred<AccountProfilePayload>()
        let store = VideoLikeStore()
        let client = AccountSessionClient(
            credentials: { AccountCredentialsSnapshot(hasCredentials: true, accountID: 42) },
            save: { _, _ in }, clear: {}, profile: { await pending.value() }
        )
        let account = AccountStore(client: client, defaults: try temporaryDefaults(), likeStore: store, monitorNetwork: false)
        let restore = Task { await account.restoreSessionIfNeeded() }
        await waitUntil { pending.isWaiting }
        store.setOverride(aid: 9, liked: true)
        let oldSession = store.sessionID
        await account.logout()
        pending.resolve(try profile())
        await restore.value
        XCTAssertFalse(account.isLoggedIn)
        XCTAssertNil(account.profile)
        XCTAssertFalse(store.isLiked(aid: 9, serverValue: false))
        store.setOverride(aid: 9, liked: true, sessionID: oldSession)
        XCTAssertFalse(store.isLiked(aid: 9, serverValue: false), "旧请求不能污染新的账号会话")
    }

    func testExplicitExpiredSessionClearsCredentials() async throws {
        var didClear = false
        let client = AccountSessionClient(
            credentials: { AccountCredentialsSnapshot(hasCredentials: true, accountID: 42) },
            save: { _, _ in }, clear: { didClear = true },
            profile: { throw BiliAPIError.apiError(code: -101, message: "expired") }
        )
        let account = AccountStore(client: client, defaults: try temporaryDefaults(), likeStore: VideoLikeStore(), monitorNetwork: false)
        await account.restoreSessionIfNeeded()
        XCTAssertTrue(didClear)
        XCTAssertFalse(account.isLoggedIn)
        XCTAssertFalse(account.isRestoringSession)
    }

    func testLikeToggleUsesDisplayedOverrideInsteadOfStaleRelation() async throws {
        let detail = try video()
        let likes = VideoLikeStore()
        likes.setOverride(aid: detail.aid, liked: true)
        var requests: [Bool] = []
        let model = VideoDetailViewModel(bvid: detail.bvid, likeStore: likes,
            fetchDetail: { _ in detail },
            fetchRelation: { _, _ in self.unlikedRelation },
            sendLike: { _, liked in requests.append(liked) })
        await model.load()
        XCTAssertTrue(model.displayedIsLiked)
        await model.toggleLike(isLoggedIn: true)
        XCTAssertEqual(requests, [false])
        XCTAssertFalse(model.displayedIsLiked)
        XCTAssertEqual(model.likeCount, detail.stat.like - 1)
    }

    func testLikeWaitsForRelationAndDoesNotDoubleSubmit() async throws {
        let detail = try video()
        let pending = Deferred<VideoRelation>()
        var requests: [Bool] = []
        let model = VideoDetailViewModel(bvid: detail.bvid, likeStore: VideoLikeStore(),
            fetchDetail: { _ in detail }, fetchRelation: { _, _ in await pending.value() },
            sendLike: { _, liked in requests.append(liked) })
        await model.load()
        let first = Task { await model.toggleLike(isLoggedIn: true) }
        await waitUntil { pending.isWaiting }
        await model.toggleLike(isLoggedIn: true)
        XCTAssertTrue(requests.isEmpty)
        pending.resolve(VideoRelation(attention: false, favorite: false, like: true, dislike: false, coin: 0))
        await first.value
        XCTAssertEqual(requests, [false])
    }

    func testOldDynamicPageCannotReplaceRefreshedCursor() async throws {
        let initial = try feed(id: "old", offset: "old-cursor")
        let refreshed = try feed(id: "new", offset: "new-cursor")
        let stale = try feed(id: "stale", offset: "stale-cursor")
        let next = try feed(id: "next", offset: "next-cursor")
        let pending = Deferred<DynamicFeedPage>()
        var requests: [(Int, String?)] = []
        let model = DynamicFeedModel(source: .following, fetchFeed: { _, page, offset in
            requests.append((page, offset))
            switch requests.count {
            case 1: return initial
            case 2: return await pending.value()
            case 3: return refreshed
            default: return next
            }
        })
        await model.loadInitial()
        let oldPage = Task { await model.loadMoreIfNeeded(current: initial.entries[0]) }
        await waitUntil { pending.isWaiting }
        await model.refresh()
        pending.resolve(stale)
        await oldPage.value
        XCTAssertEqual(model.entries.map(\.id), ["new"])
        await model.loadMoreIfNeeded(current: refreshed.entries[0])
        XCTAssertEqual(requests.last?.0, 2)
        XCTAssertEqual(requests.last?.1, "new-cursor")
        XCTAssertEqual(model.entries.map(\.id), ["new", "next"])
    }

    func testOldRefreshCannotClearNewLoadingFlag() async throws {
        let old = Deferred<DynamicFeedPage>(), new = Deferred<DynamicFeedPage>()
        var calls = 0
        let model = DynamicFeedModel(source: .following, fetchFeed: { _, _, _ in
            calls += 1
            return await (calls == 1 ? old : new).value()
        })
        let first = Task { await model.refresh() }
        await waitUntil { old.isWaiting }
        let second = Task { await model.refresh() }
        await waitUntil { new.isWaiting }
        old.resolve(try feed(id: "old", offset: "old"))
        await first.value
        XCTAssertTrue(model.isLoading)
        new.resolve(try feed(id: "new", offset: "new"))
        await second.value
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.entries.map(\.id), ["new"])
    }

    func testOldAccountDynamicResponseIsDiscarded() async throws {
        let likes = VideoLikeStore()
        let pending = Deferred<DynamicFeedPage>()
        let model = DynamicFeedModel(source: .following, likeStore: likes,
                                     fetchFeed: { _, _, _ in await pending.value() })
        let request = Task { await model.loadInitial() }
        await waitUntil { pending.isWaiting }
        likes.resetSession()
        pending.resolve(try feed(id: "old-account", offset: "old"))
        await request.value
        XCTAssertTrue(model.entries.isEmpty)
    }

    func testLateLikeFailureCannotOverwriteNewAccountOverride() async throws {
        let likes = VideoLikeStore()
        let pending = Deferred<Bool>()
        let detail = try video()
        let model = VideoDetailViewModel(bvid: detail.bvid, likeStore: likes,
            fetchDetail: { _ in detail }, fetchRelation: { _, _ in self.unlikedRelation },
            sendLike: { _, _ in
                _ = await pending.value()
                throw URLError(.timedOut)
            })
        await model.load()
        let request = Task { await model.toggleLike(isLoggedIn: true) }
        await waitUntil { pending.isWaiting }
        likes.resetSession()
        likes.setOverride(aid: detail.aid, liked: true)
        pending.resolve(true)
        await request.value
        XCTAssertTrue(likes.isLiked(aid: detail.aid, serverValue: false))
    }

    func testPlaybackErrorAfterFirstFrameRemainsVisibleAndRetryPreservesPosition() async {
        let player = PlayerViewModel(bvid: "audit-fake", cid: 1,
            playbackURLLoader: { _, _ in throw URLError(.notConnectedToInternet) },
            watchProgressReporter: { _, _, _ in })
        defer { player.stop() }
        let oldSession = player.session
        let oldCallback = oldSession.onEvent
        oldCallback?(.firstFrame)
        oldCallback?(.position(23))
        oldCallback?(.buffering(true))
        XCTAssertTrue(player.isBuffering)
        oldCallback?(.error("connection lost"))
        XCTAssertEqual(player.errorMessage, "connection lost")
        XCTAssertFalse(player.isBuffering)
        player.play()
        XCTAssertFalse(player.isPlaying)
        await player.retry()
        XCTAssertFalse(player.session === oldSession)
        XCTAssertEqual(player.currentTime, 23)
        XCTAssertNotNil(player.errorMessage, "重试失败仍提供错误与重试入口")
        oldCallback?(.position(0))
        oldCallback?(.firstFrame)
        XCTAssertEqual(player.currentTime, 23)
        XCTAssertFalse(player.hasRenderedFirstFrame)
    }

    func testRetryLoadCommandUsesMPVOptionPositionAndFiniteTime() {
        XCTAssertEqual(PlaybackLoadCommand.arguments(url: "https://example.com/v", startTime: 23.5),
                       ["loadfile", "https://example.com/v", "replace", "-1", "start=23.500"])
        XCTAssertEqual(PlaybackLoadCommand.arguments(url: "x", startTime: .nan).last, "start=0.000")
    }

    private var unlikedRelation: VideoRelation {
        VideoRelation(attention: false, favorite: false, like: false, dislike: false, coin: 0)
    }

    private func temporaryDefaults() throws -> UserDefaults {
        let suite = "neobili.audit.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func comment(_ id: Int) throws -> Comment {
        try decode("""
        {"rpid":\(id),"ctime":1,"like":0,"rcount":0,"member":{"uname":"test","avatar":""},"content":{"message":"test"}}
        """)
    }

    private func profile() throws -> AccountProfilePayload {
        try decode(#"{"isLogin":true,"mid":42,"uname":"Test Account"}"#)
    }

    private func video() throws -> VideoDetail {
        try decode(#"""
        {"bvid":"BVTest","aid":9,"cid":1,"title":"test","desc":"","pic":"","duration":60,
        "pubdate":1,"owner":{"mid":42,"name":"test","face":""},
        "stat":{"view":1,"danmaku":0,"like":10,"favorite":0,"coin":0,"share":0,"reply":0},"pages":[]}
        """#)
    }

    func testStagedDynamicRefreshKeepsOldCardsAndBlocksPaginationUntilCommit() async throws {
        let first = try feed(id: "1", offset: "old")
        let second = try feed(id: "2", offset: "new")
        var calls = 0
        let model = DynamicFeedModel(source: .following, likeStore: VideoLikeStore(), fetchFeed: { _, _, _ in
            calls += 1
            return calls == 1 ? first : second
        })
        await model.loadInitial()
        let stagingID = UUID()
        await model.refresh(staged: true, stagingID: stagingID)
        model.commitStagedRefresh(id: UUID())
        XCTAssertEqual(model.entries.map(\.id), ["1"], "旧任务不能提交新一轮暂存结果")
        await model.loadMoreIfNeeded(current: first.entries[0])
        XCTAssertEqual(calls, 2)
        model.commitStagedRefresh()
        XCTAssertEqual(model.entries.map(\.id), ["2"])
        model.commitStagedRefresh()
        XCTAssertEqual(model.entries.map(\.id), ["2"])
    }

    func testFailedStagedDynamicRefreshPreservesExistingCards() async throws {
        let first = try feed(id: "1", offset: "old")
        var calls = 0
        let model = DynamicFeedModel(source: .following, likeStore: VideoLikeStore(), fetchFeed: { _, _, _ in
            calls += 1
            if calls > 1 { throw URLError(.notConnectedToInternet) }
            return first
        })
        await model.loadInitial()
        await model.refresh(staged: true)
        model.commitStagedRefresh()
        XCTAssertEqual(model.entries.map(\.id), ["1"])
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
    }

    private func feed(id: String, offset: String) throws -> DynamicFeedPage {
        try decode("""
        {"has_more":true,"offset":"\(offset)","items":[{"id_str":"\(id)","type":"DYNAMIC_TYPE_WORD",
        "modules":{"module_dynamic":{"desc":{"text":"test"}}}}]}
        """)
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<10_000 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("异步请求未在预期时间进入等待状态")
    }
}

@MainActor
private final class Deferred<Value> {
    private var continuation: CheckedContinuation<Value, Never>?
    var isWaiting: Bool { continuation != nil }

    func value() async -> Value {
        await withCheckedContinuation { continuation = $0 }
    }

    func resolve(_ value: Value) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
