import XCTest
@testable import NeoBili

@MainActor
final class LiveFeedTests: XCTestCase {
    func testFollowingSwitchDiscardsOldRecommendationAndItsPagination() async throws {
        let probe = LiveFeedRequestProbe()
        defer { Task { await probe.cancelAll() } }
        let model = LiveFeedModel { try await probe.load(source: $0, page: $1) }
        let old = Task { await model.loadInitial() }
        try await waitUntil { await probe.isPending(.recommended, page: 1) }

        model.select(.following)
        XCTAssertTrue(model.rooms.isEmpty)
        let current = Task { await model.loadInitial() }
        try await waitUntil { await probe.isPending(.following, page: 1) }
        await probe.resolve(.following, page: 1, rooms: [room(23)], hasMore: false)
        await current.value
        await probe.resolve(.recommended, page: 1, rooms: [room(1)], hasMore: true)
        await old.value

        XCTAssertEqual(model.source, .following)
        XCTAssertEqual(model.rooms.map(\.roomID), [23])
        XCTAssertFalse(model.hasMore)
        XCTAssertFalse(model.isLoading)
    }

    func testRefreshInvalidatesPendingPageAndPreservesFreshResults() async throws {
        let probe = LiveFeedRequestProbe()
        defer { Task { await probe.cancelAll() } }
        let model = LiveFeedModel { try await probe.load(source: $0, page: $1) }
        let first = Task { await model.loadInitial() }
        try await waitUntil { await probe.isPending(.recommended, page: 1) }
        await probe.resolve(.recommended, page: 1, rooms: [room(1)], hasMore: true)
        await first.value

        let oldPage = Task { await model.loadMore() }
        try await waitUntil { await probe.isPending(.recommended, page: 2) }
        let refresh = Task { await model.refresh() }
        try await waitUntil { await probe.isPending(.recommended, page: 1) }
        await probe.resolve(.recommended, page: 1, rooms: [room(8)], hasMore: true)
        await refresh.value
        await probe.fail(.recommended, page: 2)
        await oldPage.value

        XCTAssertEqual(model.rooms.map(\.roomID), [8])
        XCTAssertEqual(model.loadedPage, 1)
        XCTAssertNil(model.paginationError, "A superseded page cannot display an error on the refreshed feed")
        XCTAssertFalse(model.isLoadingMore)
    }

    func testStagedRefreshKeepsOldCardsUntilExitCompletesAndBlocksPagination() async throws {
        let probe = LiveFeedRequestProbe()
        defer { Task { await probe.cancelAll() } }
        let model = LiveFeedModel { try await probe.load(source: $0, page: $1) }
        let initial = Task { await model.loadInitial() }
        try await waitUntil { await probe.isPending(.recommended, page: 1) }
        await probe.resolve(.recommended, page: 1, rooms: [room(1)], hasMore: true)
        await initial.value
        let previousGeneration = model.entranceGeneration

        let refresh = Task { await model.refresh(staged: true) }
        try await waitUntil { await probe.isPending(.recommended, page: 1) }
        await probe.resolve(.recommended, page: 1, rooms: [room(8)], hasMore: false)
        await refresh.value
        XCTAssertEqual(model.rooms.map(\.roomID), [1], "快请求不能让新卡片参与旧列表淡出")
        XCTAssertEqual(model.entranceGeneration, previousGeneration)
        await model.loadMore()
        let requestCount = await probe.requestCount
        XCTAssertEqual(requestCount, 2, "退出动画期间不能对仍显示的旧卡片翻页")

        model.commitStagedRefresh()
        XCTAssertEqual(model.rooms.map(\.roomID), [8])
        XCTAssertFalse(model.hasMore)
        XCTAssertEqual(model.entranceGeneration, previousGeneration + 1)
        model.commitStagedRefresh()
        XCTAssertEqual(model.entranceGeneration, previousGeneration + 1, "同一刷新只发布一次入场批次")
    }

    func testStagedRefreshCannotRestorePreviousSourceAfterSwitch() async throws {
        let model = LiveFeedModel { _, page in
            LiveRoomPage(rooms: [LiveRoom(roomID: 1, title: "推荐", username: "主播")], page: page, hasMore: false)
        }
        await model.loadInitial()
        await model.refresh(staged: true)
        model.select(.following)
        model.commitStagedRefresh()
        XCTAssertEqual(model.source, .following)
        XCTAssertTrue(model.rooms.isEmpty)
        XCTAssertEqual(model.loadedPage, 0)
        XCTAssertEqual(LiveFeedModel.Source.allCases, [.recommended, .following])
    }

    func testCancelledExitDiscardsStagedSnapshotWithoutChangingVisibleCards() async throws {
        let probe = LiveFeedRequestProbe()
        defer { Task { await probe.cancelAll() } }
        let model = LiveFeedModel { try await probe.load(source: $0, page: $1) }
        let initial = Task { await model.loadInitial() }
        try await waitUntil { await probe.isPending(.recommended, page: 1) }
        await probe.resolve(.recommended, page: 1, rooms: [room(1)], hasMore: true)
        await initial.value
        let previousGeneration = model.entranceGeneration

        let refresh = Task { await model.refresh(staged: true) }
        try await waitUntil { await probe.isPending(.recommended, page: 1) }
        await probe.resolve(.recommended, page: 1, rooms: [room(8)], hasMore: false)
        await refresh.value
        model.discardStagedRefresh()
        model.commitStagedRefresh()
        XCTAssertEqual(model.rooms.map(\.roomID), [1])
        XCTAssertEqual(model.entranceGeneration, previousGeneration)
        XCTAssertTrue(model.hasMore)
    }

    func testPaginationDeduplicatesRetriesSamePageAndStopsRepeatedTerminalPage() async throws {
        let probe = LiveFeedRequestProbe()
        defer { Task { await probe.cancelAll() } }
        let model = LiveFeedModel { try await probe.load(source: $0, page: $1) }
        let first = Task { await model.loadInitial() }
        try await waitUntil { await probe.isPending(.recommended, page: 1) }
        await probe.resolve(.recommended, page: 1, rooms: [room(1), room(1), room(2)], hasMore: true)
        await first.value
        XCTAssertEqual(model.rooms.map(\.id), [1, 2])

        let failed = Task { await model.loadMore() }
        try await waitUntil { await probe.isPending(.recommended, page: 2) }
        await model.loadMore()
        let requestCount = await probe.requestCount
        XCTAssertEqual(requestCount, 2, "Visible neighboring cards must share the in-flight page")
        await probe.fail(.recommended, page: 2)
        await failed.value
        XCTAssertEqual(model.loadedPage, 1)
        XCTAssertNotNil(model.paginationError)

        let retry = Task { await model.loadMore() }
        try await waitUntil { await probe.isPending(.recommended, page: 2) }
        await probe.resolve(.recommended, page: 2, rooms: [room(2), room(3), room(3)], hasMore: true)
        await retry.value
        XCTAssertEqual(model.rooms.map(\.id), [1, 2, 3])
        XCTAssertNil(model.paginationError)

        let repeated = Task { await model.loadMore() }
        try await waitUntil { await probe.isPending(.recommended, page: 3) }
        await probe.resolve(.recommended, page: 3, rooms: [room(2), room(3)], hasMore: true)
        await repeated.value
        XCTAssertFalse(model.hasMore)
        await model.loadMore()
        let terminalCount = await probe.requestCount
        XCTAssertEqual(terminalCount, 4)
    }

    func testFollowingFindsLaterLiveRoomsAfterEntireFirstPageIsOffline() async throws {
        let probe = LiveFeedRequestProbe()
        defer { Task { await probe.cancelAll() } }
        let model = LiveFeedModel { try await probe.load(source: $0, page: $1) }
        model.select(.following)
        let initial = Task { await model.loadInitial() }
        try await waitUntil { await probe.isPending(.following, page: 1) }
        await probe.resolve(.following, page: 1, rooms: [], hasMore: true, sourceRoomIDs: [91, 92])
        try await waitUntil { await probe.isPending(.following, page: 2) }
        XCTAssertTrue(model.isLoading)
        await probe.resolve(.following, page: 2, rooms: [room(3)], hasMore: false, sourceRoomIDs: [3, 93])
        await initial.value
        XCTAssertEqual(model.rooms.map(\.roomID), [3])
        XCTAssertEqual(model.loadedPage, 2)
        XCTAssertFalse(model.hasMore)
    }

    func testFollowingPaginationSkipsOfflinePageWithoutDroppingLaterLiveRooms() async throws {
        let probe = LiveFeedRequestProbe()
        defer { Task { await probe.cancelAll() } }
        let model = LiveFeedModel { try await probe.load(source: $0, page: $1) }
        model.select(.following)
        let initial = Task { await model.loadInitial() }
        try await waitUntil { await probe.isPending(.following, page: 1) }
        await probe.resolve(.following, page: 1, rooms: [room(1)], hasMore: true, sourceRoomIDs: [1, 91])
        await initial.value
        let previousGeneration = model.entranceGeneration
        let next = Task { await model.loadMore() }
        try await waitUntil { await probe.isPending(.following, page: 2) }
        await probe.resolve(.following, page: 2, rooms: [], hasMore: true, sourceRoomIDs: [92, 93])
        try await waitUntil { await probe.isPending(.following, page: 3) }
        await probe.resolve(.following, page: 3, rooms: [room(4)], hasMore: false, sourceRoomIDs: [4, 94])
        await next.value
        XCTAssertEqual(model.rooms.map(\.roomID), [1, 4])
        XCTAssertEqual(model.loadedPage, 3)
        XCTAssertFalse(model.hasMore)
        XCTAssertEqual(model.entranceGeneration, previousGeneration, "自动越过下播页不重播已有卡片")
    }

    func testRepeatedRawOfflinePageEndsPaginationEvenWhenServerClaimsMore() async throws {
        let probe = LiveFeedRequestProbe()
        defer { Task { await probe.cancelAll() } }
        let model = LiveFeedModel { try await probe.load(source: $0, page: $1) }
        model.select(.following)
        let initial = Task { await model.loadInitial() }
        try await waitUntil { await probe.isPending(.following, page: 1) }
        await probe.resolve(.following, page: 1, rooms: [], hasMore: true, sourceRoomIDs: [91, 92])
        try await waitUntil { await probe.isPending(.following, page: 2) }
        await probe.resolve(.following, page: 2, rooms: [], hasMore: true, sourceRoomIDs: [92, 91])
        await initial.value
        XCTAssertTrue(model.rooms.isEmpty)
        XCTAssertFalse(model.hasMore)
        await model.loadMore()
        let requestCount = await probe.requestCount
        XCTAssertEqual(requestCount, 2)
    }

    func testActuallyEmptySourcePageStopsInsteadOfStartingAnUnboundedScan() async {
        let model = LiveFeedModel { _, page in
            LiveRoomPage(rooms: [], page: page, hasMore: true, sourceRoomIDs: [])
        }
        model.select(.following)
        await model.loadInitial()
        XCTAssertTrue(model.rooms.isEmpty)
        XCTAssertFalse(model.hasMore)
        XCTAssertEqual(model.loadedPage, 1)
    }

    func testSignOutImmediatelyClearsFollowingAndIgnoresOldAccountResponse() async throws {
        let probe = LiveFeedRequestProbe()
        defer { Task { await probe.cancelAll() } }
        let model = LiveFeedModel { try await probe.load(source: $0, page: $1) }
        model.synchronizeAccount(sessionID: UUID(), isLoggedIn: true)
        model.select(.following)
        let following = Task { await model.loadInitial() }
        try await waitUntil { await probe.isPending(.following, page: 1) }
        model.synchronizeAccount(sessionID: UUID(), isLoggedIn: false)
        XCTAssertEqual(model.source, .recommended)
        XCTAssertTrue(model.rooms.isEmpty)
        await probe.resolve(.following, page: 1, rooms: [room(9)], hasMore: true)
        await following.value
        XCTAssertTrue(model.rooms.isEmpty)
        XCTAssertEqual(model.loadedPage, 0)
        XCTAssertFalse(model.isLoading)
    }

    func testCancelledFeedDoesNotBecomeUserFacingFailure() async {
        let model = LiveFeedModel { _, _ in throw CancellationError() }
        await model.loadInitial()
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
        XCTAssertEqual(model.loadedPage, 0)
    }

    private func room(_ id: Int) -> LiveRoom { LiveRoom(roomID: id, title: "房间 \(id)", username: "主播") }

    private func waitUntil(_ predicate: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Live feed request did not start")
        throw CancellationError()
    }
}

private actor LiveFeedRequestProbe {
    private struct Request: Hashable {
        let source: LiveFeedModel.Source
        let page: Int
    }
    private var pending: [Request: CheckedContinuation<LiveRoomPage, any Error>] = [:]
    private(set) var requestCount = 0

    func load(source: LiveFeedModel.Source, page: Int) async throws -> LiveRoomPage {
        requestCount += 1
        return try await withCheckedThrowingContinuation {
            pending[Request(source: source, page: page)] = $0
        }
    }

    func isPending(_ source: LiveFeedModel.Source, page: Int) -> Bool {
        pending[Request(source: source, page: page)] != nil
    }

    func resolve(_ source: LiveFeedModel.Source, page: Int, rooms: [LiveRoom], hasMore: Bool,
                 sourceRoomIDs: [Int]? = nil) {
        pending.removeValue(forKey: Request(source: source, page: page))?
            .resume(returning: LiveRoomPage(rooms: rooms, page: page, hasMore: hasMore,
                                           sourceRoomIDs: sourceRoomIDs))
    }

    func fail(_ source: LiveFeedModel.Source, page: Int) {
        pending.removeValue(forKey: Request(source: source, page: page))?
            .resume(throwing: URLError(.notConnectedToInternet))
    }

    func cancelAll() {
        let continuations = pending.values
        pending.removeAll()
        for continuation in continuations { continuation.resume(throwing: CancellationError()) }
    }
}
