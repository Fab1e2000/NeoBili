import Foundation

// Only the unused default network entry point is stubbed. Every test injects a
// controlled loader into the production FollowedLiveDirectory implementation.
enum LiveAPI {
    static func followed(page: Int) async throws -> LiveRoomPage {
        preconditionFailure("Offline regression must never call a network loader")
    }
}

@MainActor
private final class DirectoryLoader {
    private(set) var requests: [Int] = []
    private var pending: [Int: CheckedContinuation<LiveRoomPage, Error>] = [:]

    func load(_ page: Int) async throws -> LiveRoomPage {
        let ticket = requests.count
        requests.append(page)
        return try await withCheckedThrowingContinuation { pending[ticket] = $0 }
    }

    func succeed(_ ticket: Int, rooms: [LiveRoom], more: Bool = false, sourceIDs: [Int]? = nil) {
        pending.removeValue(forKey: ticket)?.resume(returning: LiveRoomPage(
            rooms: rooms, page: requests[ticket], hasMore: more, sourceRoomIDs: sourceIDs
        ))
    }

    func fail(_ ticket: Int) {
        pending.removeValue(forKey: ticket)?.resume(throwing: URLError(.timedOut))
    }
}

@MainActor
private final class DirectoryClock {
    var date = Date(timeIntervalSince1970: 1_000)
}

@main @MainActor
enum FollowedLiveDirectoryRegression {
    nonisolated static func room(_ uid: Int, id: Int? = nil, live: Bool = true) -> LiveRoom {
        LiveRoom(roomID: id ?? uid, title: "Room \(uid)", username: "UP \(uid)", uid: uid,
                 liveStatus: live ? 1 : 0)
    }

    static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        preconditionFailure("Controlled loader timed out")
    }

    private static func complete(_ directory: FollowedLiveDirectory, loader: DirectoryLoader,
                         rooms: [LiveRoom], force: Bool = false) async {
        let ticket = loader.requests.count
        let task = Task { await directory.refresh(force: force) }
        await waitUntil { loader.requests.count == ticket + 1 }
        loader.succeed(ticket, rooms: rooms)
        await task.value
    }

    static func main() async {
        await progressivePagesAndSuccessfulOfflineRemoval()
        await failureAndRepeatedFilteredPagePreserveKnownRooms()
        await concurrentAndForcedRefreshes()
        await resetAndCancellationIgnoreLateResults()
        await successCacheAndPageLimit()
        print("Followed live directory regression passed: progressive pages, live filtering, failures, raw-page repetition, overlap, reset, cancellation, cache, and page cap")
    }

    static func progressivePagesAndSuccessfulOfflineRemoval() async {
        let loader = DirectoryLoader()
        let directory = FollowedLiveDirectory(loader: { try await loader.load($0) })
        await complete(directory, loader: loader, rooms: [room(9)])
        let refresh = Task { await directory.refresh(force: true) }
        await waitUntil { loader.requests.count == 2 }
        loader.succeed(1, rooms: [room(1), room(8, live: false), room(0, id: 88)], more: true)
        await waitUntil { loader.requests.count == 3 }
        precondition(directory.rooms.map(\.uid) == [1, 9], "First-page live UPs must show while the next page is still suspended")
        loader.succeed(2, rooms: [], more: true, sourceIDs: [81, 82])
        await waitUntil { loader.requests.count == 4 }
        precondition(directory.rooms.map(\.uid) == [1, 9], "An all-offline filtered page is not the end of pagination")
        loader.succeed(3, rooms: [room(1, id: 11), room(2)])
        await refresh.value
        precondition(loader.requests == [1, 1, 2, 3])
        precondition(directory.rooms.map(\.uid) == [1, 2], "Only a complete scan removes unmatched cached UPs; duplicate users appear once")
        await complete(directory, loader: loader, rooms: [], force: true)
        precondition(directory.rooms.isEmpty, "A successful empty snapshot can confirm every UP is offline")
    }

    static func failureAndRepeatedFilteredPagePreserveKnownRooms() async {
        let loader = DirectoryLoader()
        let directory = FollowedLiveDirectory(loader: { try await loader.load($0) })
        await complete(directory, loader: loader, rooms: [room(10), room(20)])
        let refresh = Task { await directory.refresh(force: true) }
        await waitUntil { loader.requests.count == 2 }
        loader.succeed(1, rooms: [room(30)], more: true)
        await waitUntil { loader.requests.count == 3 }
        loader.fail(2)
        await refresh.value
        precondition(directory.rooms.map(\.uid) == [30, 10, 20], "A later page failure retains both newly confirmed and previously known live UPs")

        let repeated = Task { await directory.refresh(force: true) }
        await waitUntil { loader.requests.count == 4 }
        loader.succeed(3, rooms: [room(40)], more: true)
        await waitUntil { loader.requests.count == 5 }
        loader.succeed(4, rooms: [], more: true, sourceIDs: [70, 71])
        await waitUntil { loader.requests.count == 6 }
        loader.succeed(5, rooms: [], more: true, sourceIDs: [71, 70])
        await repeated.value
        precondition(loader.requests.count == 6, "Repeated raw pages stop even when offline filtering hides every room")
        precondition(directory.rooms.map(\.uid) == [40, 30, 10, 20], "An incomplete repeated-page scan must not clear unvisited UPs")
    }

    static func concurrentAndForcedRefreshes() async {
        let loader = DirectoryLoader()
        let directory = FollowedLiveDirectory(loader: { try await loader.load($0) })
        let older = Task { await directory.refresh() }
        await waitUntil { loader.requests.count == 1 }
        await directory.refresh()
        precondition(loader.requests.count == 1, "Ordinary concurrent refreshes must share the pending request")
        let newer = Task { await directory.refresh(force: true) }
        await waitUntil { loader.requests.count == 2 }
        loader.succeed(1, rooms: [room(2)])
        await newer.value
        loader.succeed(0, rooms: [room(1)])
        await older.value
        precondition(directory.rooms.map(\.uid) == [2], "A force-refresh result must not be overwritten by the earlier request")
    }

    static func resetAndCancellationIgnoreLateResults() async {
        let loader = DirectoryLoader()
        let directory = FollowedLiveDirectory(loader: { try await loader.load($0) })
        let old = Task { await directory.refresh() }
        await waitUntil { loader.requests.count == 1 }
        directory.reset()
        let current = Task { await directory.refresh() }
        await waitUntil { loader.requests.count == 2 }
        loader.succeed(0, rooms: [room(1)])
        await old.value
        precondition(directory.rooms.isEmpty, "Reset must ignore an old account's late response")
        await directory.refresh()
        precondition(loader.requests.count == 2, "The old request's cleanup must not clear the new in-flight marker")
        loader.succeed(1, rooms: [room(2)], more: true)
        await waitUntil { loader.requests.count == 3 }
        precondition(directory.rooms.map(\.uid) == [2])
        current.cancel()
        loader.succeed(2, rooms: [room(3)])
        await current.value
        precondition(directory.rooms.map(\.uid) == [2], "Cancellation discards the suspended result without erasing confirmed earlier pages")
        await complete(directory, loader: loader, rooms: [room(4)])
        precondition(directory.rooms.map(\.uid) == [4], "A cancelled scan must leave the directory refreshable")
        directory.reset()
        precondition(directory.rooms.isEmpty)
        await complete(directory, loader: loader, rooms: [room(5)])
        precondition(directory.rooms.map(\.uid) == [5], "Reset clears the successful snapshot's cache window")
    }

    static func successCacheAndPageLimit() async {
        let clock = DirectoryClock()
        let loader = DirectoryLoader()
        let directory = FollowedLiveDirectory(loader: { try await loader.load($0) }, now: { clock.date })
        await complete(directory, loader: loader, rooms: [room(1)])
        await directory.refresh()
        precondition(loader.requests.count == 1)
        clock.date.addTimeInterval(60)
        await complete(directory, loader: loader, rooms: [room(2)])
        clock.date.addTimeInterval(-100)
        await complete(directory, loader: loader, rooms: [room(3)])
        precondition(directory.rooms.map(\.uid) == [3], "Clock rollback cannot keep a stale cache indefinitely")

        let count = PageCount()
        let capped = FollowedLiveDirectory(loader: { page in
            await count.add()
            return LiveRoomPage(rooms: page == 1 ? [room(7)] : [], page: page,
                                hasMore: true, sourceRoomIDs: [page])
        })
        await capped.refresh()
        let calls = await count.value
        precondition(calls == 100, "Malformed endless pagination must have a bounded request count")
        precondition(capped.rooms.map(\.uid) == [7], "Reaching the cap must retain already-published live UPs")
    }
}

private actor PageCount {
    private(set) var value = 0
    func add() { value += 1 }
}
