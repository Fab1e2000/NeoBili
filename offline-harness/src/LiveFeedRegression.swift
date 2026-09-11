import Foundation

/// Network-only stand-ins; all pagination, staging and request invalidation run
/// the production LiveFeedModel and LiveRoomPage without UIKit or HTTP.
enum LiveAPI {
    static func recommended(page: Int = 1) async throws -> LiveRoomPage { fatalError("Unexpected network dependency") }
    static func followed(page: Int = 1) async throws -> LiveRoomPage { fatalError("Unexpected network dependency") }
}

extension Error {
    var isCancellation: Bool {
        self is CancellationError || (self as? URLError)?.code == .cancelled
    }
}

@main @MainActor
struct LiveFeedRegression {
    static func main() async throws {
        precondition(LiveFeedModel.Source.allCases == [.recommended, .following])
        try await filteredFirstPage()
        try await filteredNextPage()
        await repeatedAndEmptySourcePages()
        await stagedRefresh()
        try await staleSourceResponse()
        print("PASS  直播仅推荐/关注；筛空分页、重复页终止、刷新暂存与旧请求隔离")
    }

    private static func room(_ id: Int) -> LiveRoom {
        LiveRoom(roomID: id, title: "房间 \(id)", username: "主播", uid: id)
    }

    private static func filteredFirstPage() async throws {
        let pages = LiveFeedPageFixture([
            1: LiveRoomPage(rooms: [], page: 1, hasMore: true, sourceRoomIDs: [90, 91]),
            2: LiveRoomPage(rooms: [room(2)], page: 2, hasMore: false, sourceRoomIDs: [2, 92])
        ])
        let model = LiveFeedModel { _, page in try await pages.load(page) }
        model.select(.following)
        await model.loadInitial()
        precondition(model.rooms.map(\.roomID) == [2] && model.loadedPage == 2 && !model.hasMore)
        let requests = await pages.requests
        precondition(requests == [1, 2])
    }

    private static func filteredNextPage() async throws {
        let pages = LiveFeedPageFixture([
            1: LiveRoomPage(rooms: [room(1)], page: 1, hasMore: true, sourceRoomIDs: [1, 90]),
            2: LiveRoomPage(rooms: [], page: 2, hasMore: true, sourceRoomIDs: [91, 92]),
            3: LiveRoomPage(rooms: [room(3)], page: 3, hasMore: false, sourceRoomIDs: [3, 93])
        ])
        let model = LiveFeedModel { _, page in try await pages.load(page) }
        model.select(.following)
        await model.loadInitial()
        let entrance = model.entranceGeneration
        await model.loadMore()
        precondition(model.rooms.map(\.roomID) == [1, 3] && model.loadedPage == 3 && !model.hasMore)
        precondition(model.entranceGeneration == entrance)
    }

    private static func repeatedAndEmptySourcePages() async {
        let pages = LiveFeedPageFixture([
            1: LiveRoomPage(rooms: [], page: 1, hasMore: true, sourceRoomIDs: [90, 91]),
            2: LiveRoomPage(rooms: [], page: 2, hasMore: true, sourceRoomIDs: [91, 90])
        ])
        let repeated = LiveFeedModel { _, page in try await pages.load(page) }
        repeated.select(.following)
        await repeated.loadInitial()
        await repeated.loadMore()
        precondition(repeated.rooms.isEmpty && !repeated.hasMore && repeated.loadedPage == 2)
        let requests = await pages.requests
        precondition(requests == [1, 2])
        let empty = LiveFeedModel { _, page in
            LiveRoomPage(rooms: [], page: page, hasMore: true, sourceRoomIDs: [])
        }
        await empty.loadInitial()
        precondition(empty.loadedPage == 1 && !empty.hasMore)
    }

    private static func stagedRefresh() async {
        let pages = LiveFeedRefreshFixture(old: room(1), new: room(2))
        let model = LiveFeedModel { _, page in await pages.load(page) }
        await model.loadInitial()
        let entrance = model.entranceGeneration
        await model.refresh(staged: true)
        precondition(model.rooms.map(\.roomID) == [1] && model.entranceGeneration == entrance)
        await model.loadMore()
        let requestsBeforeCommit = await pages.requests
        precondition(requestsBeforeCommit == 2)
        model.commitStagedRefresh()
        precondition(model.rooms.map(\.roomID) == [2] && model.entranceGeneration == entrance + 1)
        model.commitStagedRefresh()
        precondition(model.entranceGeneration == entrance + 1)
        await model.refresh(staged: true)
        model.discardStagedRefresh()
        model.commitStagedRefresh()
        precondition(model.entranceGeneration == entrance + 1)
        await model.refresh(staged: true)
        model.select(.following)
        model.commitStagedRefresh()
        precondition(model.rooms.isEmpty && model.loadedPage == 0)
    }

    private static func staleSourceResponse() async throws {
        let gate = LiveFeedResponseGate()
        let model = LiveFeedModel { _, _ in try await gate.load() }
        let old = Task { await model.loadInitial() }
        try await waitUntil { await gate.count == 1 }
        model.select(.following)
        let fresh = Task { await model.loadInitial() }
        try await waitUntil { await gate.count == 2 }
        await gate.resolve(2, room: room(2))
        await fresh.value
        await gate.resolve(1, room: room(1))
        await old.value
        precondition(model.source == .following && model.rooms.map(\.roomID) == [2])
    }

    private static func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        preconditionFailure("Live feed regression request did not begin")
    }
}

private actor LiveFeedPageFixture {
    let pages: [Int: LiveRoomPage]
    private(set) var requests: [Int] = []
    init(_ pages: [Int: LiveRoomPage]) { self.pages = pages }
    func load(_ page: Int) throws -> LiveRoomPage {
        requests.append(page)
        guard let result = pages[page] else { throw URLError(.badServerResponse) }
        return result
    }
}

private actor LiveFeedRefreshFixture {
    let old: LiveRoom
    let new: LiveRoom
    private(set) var requests = 0
    init(old: LiveRoom, new: LiveRoom) { self.old = old; self.new = new }
    func load(_ page: Int) -> LiveRoomPage {
        requests += 1
        return LiveRoomPage(rooms: [requests == 1 ? old : new], page: page, hasMore: requests == 1)
    }
}

private actor LiveFeedResponseGate {
    private(set) var count = 0
    private var pending: [Int: CheckedContinuation<LiveRoomPage, any Error>] = [:]
    func load() async throws -> LiveRoomPage {
        count += 1
        let request = count
        return try await withCheckedThrowingContinuation { pending[request] = $0 }
    }
    func resolve(_ request: Int, room: LiveRoom) {
        pending.removeValue(forKey: request)?.resume(returning: LiveRoomPage(rooms: [room], page: 1, hasMore: false))
    }
}
