import XCTest
@testable import NeoBili

/// 注入直播目录，不请求真实账号、动态或关注接口。
@MainActor
final class FollowingLiveTests: XCTestCase {
    func testLiveUpsPrecedeUnreadUpdatesAndKeepPortalOrderWithinGroups() async throws {
        let fixture = try FollowingLiveFixture(pages: [1: page([room(3), room(4)], number: 1)])
        defer { fixture.cleanUp() }
        fixture.model.replaceUps([up(1), up(2, updated: true), up(3), up(4, updated: true)])
        await fixture.directory.refresh()

        XCTAssertEqual(fixture.model.selectionItems.map(\.id), [.all, .up(3), .up(4), .up(2), .up(1)])
        XCTAssertEqual(fixture.model.selectionItems.first { $0.id == .up(3) }?.up?.liveRoomID, 1003)
        XCTAssertEqual(fixture.model.selectionItems.first { $0.id == .up(3) }?.up?.hasUpdate, false)
        XCTAssertEqual(fixture.model.selectionItems.first { $0.id == .up(2) }?.up?.hasUpdate, true)
    }

    func testLiveUpMissingFromPortalAppearsAndCanSelectItsCachedDynamicFeed() async throws {
        let liveRoom = room(9)
        let fixture = try FollowingLiveFixture(pages: [1: page([liveRoom], number: 1)])
        defer { fixture.cleanUp() }
        fixture.model.replaceUps([up(8, updated: true)])
        await fixture.directory.refresh()
        let liveTarget = try XCTUnwrap(fixture.model.selectionItems.first { $0.id == .up(9) })

        XCTAssertEqual(fixture.model.selectionItems.map(\.id), [.all, .up(9), .up(8)])
        XCTAssertEqual(liveTarget.title, liveRoom.username)
        XCTAssertEqual(liveTarget.up?.liveRoomID, liveRoom.roomID)
        fixture.model.select(liveTarget)
        XCTAssertEqual(fixture.model.selectedTarget.id, .up(9))
        XCTAssertEqual(fixture.model.activeFeed.source, .followedUp(hostMid: 9))
        XCTAssertEqual(fixture.model.liveRoom(for: try XCTUnwrap(fixture.model.selectedUp)), liveRoom)
        let feed = fixture.model.activeFeed
        fixture.model.select(.all)
        fixture.model.select(liveTarget)
        XCTAssertTrue(feed === fixture.model.activeFeed, "Opening the live entry must not discard the UP's cached dynamic feed")
        fixture.model.replaceUps([up(8)])
        XCTAssertEqual(fixture.model.selectedTarget.id, .up(9), "A portal refresh must retain a selected UP confirmed by the live directory")
    }

    func testCompletedOfflineScanRestoresUpdateOrderAndKeepsExistingPortalSelection() async throws {
        let portal = [up(1), up(2, updated: true), up(3)]
        let fixture = try FollowingLiveFixture(pages: [1: page([room(3)], number: 1)])
        defer { fixture.cleanUp() }
        fixture.model.replaceUps(portal)
        await fixture.directory.refresh()
        fixture.model.select(try XCTUnwrap(fixture.model.selectionItems.first { $0.id == .up(3) }))
        let selectedFeed = fixture.model.activeFeed

        await fixture.loader.replace([1: page([], number: 1)])
        await fixture.directory.refresh(force: true)
        fixture.model.reconcileSelection()

        XCTAssertEqual(fixture.model.selectionItems.map(\.id), [.all, .up(2), .up(1), .up(3)])
        XCTAssertEqual(fixture.model.selectedTarget.id, .up(3))
        XCTAssertNil(fixture.model.selectedUp?.liveRoomID, "A completed offline scan must clear the selected UP's old live flag")
        XCTAssertNil(fixture.model.liveRoom(for: try XCTUnwrap(fixture.model.selectedUp)))
        XCTAssertTrue(selectedFeed === fixture.model.activeFeed)
    }

    func testCompletedOfflineScanReturnsToAllWhenSelectedUpOnlyExistedInLiveDirectory() async throws {
        let fixture = try FollowingLiveFixture(pages: [1: page([room(9)], number: 1)])
        defer { fixture.cleanUp() }
        fixture.model.replaceUps([up(8)])
        await fixture.directory.refresh()
        fixture.model.select(try XCTUnwrap(fixture.model.selectionItems.first { $0.id == .up(9) }))

        await fixture.loader.replace([1: page([], number: 1)])
        await fixture.directory.refresh(force: true)
        fixture.model.reconcileSelection()

        XCTAssertEqual(fixture.model.selectionItems.map(\.id), [.all, .up(8)])
        XCTAssertEqual(fixture.model.selectedTarget.id, .all)
        XCTAssertEqual(fixture.model.activeFeed.source, .following)
        XCTAssertTrue(fixture.model.activeFeed === fixture.model.feed)
    }

    func testAccountResetClearsLiveEntriesSelectionAndDynamicFeedCache() async throws {
        let fixture = try FollowingLiveFixture(pages: [1: page([room(9)], number: 1)])
        defer { fixture.cleanUp() }
        fixture.model.replaceUps([up(8)])
        await fixture.directory.refresh()
        let oldTarget = try XCTUnwrap(fixture.model.selectionItems.first { $0.id == .up(9) })
        fixture.model.select(oldTarget)
        let oldFeed = fixture.model.activeFeed
        let oldAllFeed = fixture.model.feed

        fixture.model.resetForAccountChange()

        XCTAssertTrue(fixture.directory.rooms.isEmpty)
        XCTAssertTrue(fixture.model.ups.isEmpty)
        XCTAssertEqual(fixture.model.selectionItems.map(\.id), [.all])
        XCTAssertEqual(fixture.model.selectedTarget.id, .all)
        XCTAssertFalse(fixture.model.feed === oldAllFeed)
        XCTAssertFalse(fixture.model.feed(for: oldTarget) === oldFeed)
        await fixture.loader.replace([1: page([room(20)], number: 1)])
        fixture.model.replaceUps([up(20)])
        await fixture.directory.refresh()
        XCTAssertEqual(fixture.model.selectionItems.map(\.id), [.all, .up(20)], "New account must not inherit previous live entries or refresh throttling")
    }

    func testAccountResetRejectsAnAlreadyPendingLiveScan() async throws {
        let pending = FollowingLivePageGate()
        defer { Task { await pending.cancelAll() } }
        let directory = FollowedLiveDirectory(loader: { _ in try await pending.load() })
        let fixture = try FollowingLiveFixture(directory: directory)
        defer { fixture.cleanUp() }
        fixture.model.replaceUps([up(8)])
        let old = Task { await directory.refresh() }
        for _ in 0..<100 {
            if await pending.isPending { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let isPending = await pending.isPending
        XCTAssertTrue(isPending)
        fixture.model.resetForAccountChange()
        await pending.resolve(page([room(9)], number: 1))
        await old.value
        XCTAssertTrue(directory.rooms.isEmpty)
        XCTAssertEqual(fixture.model.selectionItems.map(\.id), [.all])
        XCTAssertEqual(fixture.model.selectedTarget.id, .all)
    }

    private func up(_ mid: Int, updated: Bool = false) -> FollowedUp {
        FollowedUp(mid: mid, uname: "UP \(mid)", face: "", hasUpdate: updated)
    }

    private func room(_ mid: Int) -> LiveRoom {
        LiveRoom(roomID: 1000 + mid, title: "直播 \(mid)", username: "开播 UP \(mid)", uid: mid)
    }

    private func page(_ rooms: [LiveRoom], number: Int, hasMore: Bool = false) -> LiveRoomPage {
        LiveRoomPage(rooms: rooms, page: number, hasMore: hasMore)
    }
}

@MainActor
private final class FollowingLiveFixture {
    let model: FollowingViewModel
    let directory: FollowedLiveDirectory
    let loader: FollowingLivePages
    private let suite: String
    private let defaults: UserDefaults

    init(pages: [Int: LiveRoomPage] = [:], directory providedDirectory: FollowedLiveDirectory? = nil) throws {
        let suiteName = "NeoBili.FollowingLiveTests.\(UUID().uuidString)"
        let isolatedDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        suite = suiteName
        defaults = isolatedDefaults
        let pagesLoader = FollowingLivePages(pages: pages)
        loader = pagesLoader
        let selectedDirectory = providedDirectory ?? FollowedLiveDirectory(loader: { page in try await pagesLoader.load(page) })
        directory = selectedDirectory
        let readStore = FollowingReadStore(defaults: isolatedDefaults)
        readStore.configure(accountID: 42)
        model = FollowingViewModel(readStore: readStore, liveDirectory: selectedDirectory)
    }

    func cleanUp() { defaults.removePersistentDomain(forName: suite) }
}

private actor FollowingLivePages {
    private var pages: [Int: LiveRoomPage]
    init(pages: [Int: LiveRoomPage]) { self.pages = pages }
    func replace(_ pages: [Int: LiveRoomPage]) { self.pages = pages }
    func load(_ page: Int) throws -> LiveRoomPage {
        guard let result = pages[page] else { throw URLError(.resourceUnavailable) }
        return result
    }
}

private actor FollowingLivePageGate {
    private var pending: CheckedContinuation<LiveRoomPage, any Error>?
    var isPending: Bool { pending != nil }
    func load() async throws -> LiveRoomPage {
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func resolve(_ page: LiveRoomPage) { pending?.resume(returning: page); pending = nil }
    func cancelAll() { pending?.resume(throwing: CancellationError()); pending = nil }
}

@MainActor
final class FollowingAllUpsPaginationTests: XCTestCase {
    func testDeduplicatesWithinPageAndAcrossPagesAndStopsRepeatedPage() async throws {
        let loader = AllUpsPages(pages: [
            1: try page([1, 1, 2], total: 10),
            2: try page([2, 3, 3], total: 10),
            3: try page([2, 3, 3], total: 10)
        ])
        let model = FollowingAllUpsModel(mid: 42, loader: { _, page in try await loader.load(page) })
        await model.loadInitial()
        XCTAssertEqual(model.ups.map(\.mid), [1, 2])
        await model.loadMore()
        XCTAssertEqual(model.ups.map(\.mid), [1, 2, 3])
        await model.loadMore()
        XCTAssertFalse(model.hasMore)
        await model.loadMore()
        let calls = await loader.calls
        XCTAssertEqual(calls, [1, 2, 3])
    }

    func testDuplicateOnlyBoundaryAutomaticallyAdvancesToNextPage() async throws {
        let loader = AllUpsPages(pages: [
            1: try page([1, 2, 3], total: 4),
            2: try page([2, 3], total: 4),
            3: try page([4], total: 4)
        ])
        let model = FollowingAllUpsModel(mid: 42, loader: { _, page in try await loader.load(page) })
        await model.loadInitial()
        await model.loadMore()
        XCTAssertEqual(model.ups.map(\.mid), [1, 2, 3, 4])
        XCTAssertFalse(model.hasMore)
        let calls = await loader.calls
        XCTAssertEqual(calls, [1, 2, 3])
    }

    func testFailedTailRequiresExplicitRetryAndRetriesSamePage() async throws {
        let loader = AllUpsPages(pages: [1: try page([1], total: 2)])
        let model = FollowingAllUpsModel(mid: 42, loader: { _, page in try await loader.load(page) })
        await model.loadInitial()
        let last = try XCTUnwrap(model.ups.last)
        await model.loadMoreIfNeeded(current: last)
        XCTAssertNotNil(model.errorMessage)
        await model.loadMoreIfNeeded(current: last)
        let callsBeforeRetry = await loader.calls
        XCTAssertEqual(callsBeforeRetry, [1, 2])
        await loader.set(try page([2], total: 2), at: 2)
        await model.loadMore()
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.ups.map(\.mid), [1, 2])
        let calls = await loader.calls
        XCTAssertEqual(calls, [1, 2, 2])
    }

    func testCancellationDoesNotPublishIgnoredTransportResultOrConsumePage() async throws {
        let gate = AllUpsPageGate()
        let model = FollowingAllUpsModel(mid: 42, loader: { _, _ in await gate.load() })
        let task = Task { await model.loadInitial() }
        for _ in 0..<100 {
            if await gate.isPending { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let pending = await gate.isPending
        XCTAssertTrue(pending)
        task.cancel()
        await gate.resolve(try page([1], total: 1))
        await task.value
        XCTAssertTrue(model.ups.isEmpty)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
        XCTAssertTrue(model.hasMore)
    }

    private func page(_ mids: [Int], total: Int) throws -> FollowingsPage {
        let json: [String: Any] = ["list": mids.map { ["mid": $0, "uname": "UP \($0)"] }, "total": total]
        return try JSONDecoder().decode(FollowingsPage.self, from: JSONSerialization.data(withJSONObject: json))
    }
}

private actor AllUpsPages {
    private var pages: [Int: FollowingsPage]
    private(set) var calls: [Int] = []
    init(pages: [Int: FollowingsPage]) { self.pages = pages }
    func set(_ result: FollowingsPage, at page: Int) { pages[page] = result }
    func load(_ page: Int) throws -> FollowingsPage {
        calls.append(page)
        guard let result = pages[page] else { throw URLError(.notConnectedToInternet) }
        return result
    }
}

private actor AllUpsPageGate {
    private var pending: CheckedContinuation<FollowingsPage, Never>?
    var isPending: Bool { pending != nil }
    func load() async -> FollowingsPage { await withCheckedContinuation { pending = $0 } }
    func resolve(_ result: FollowingsPage) { pending?.resume(returning: result); pending = nil }
}
