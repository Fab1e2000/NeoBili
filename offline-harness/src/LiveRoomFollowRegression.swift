import Foundation

// Minimal non-UI dependencies only. swiftc compiles LiveRoomFollowModel.swift
// directly from production; no follow-state algorithm is duplicated here.
struct SpaceCard: Hashable, Sendable {
    let mid: Int
    let isFollowing: Bool
}

enum BiliAPI {
    static func spaceCard(mid: Int) async throws -> SpaceCard {
        preconditionFailure("Offline follow regression must not use a network reader")
    }
    static func modifyRelation(mid: Int, follow: Bool) async throws {
        preconditionFailure("Offline follow regression must not mutate a real account")
    }
}

extension Error {
    var isCancellation: Bool {
        self is CancellationError || (self as NSError).domain == NSURLErrorDomain && (self as NSError).code == NSURLErrorCancelled
    }
}

@MainActor
private final class FollowAPI {
    var following = true
    var readFails = false
    var writeFails = false
    private(set) var reads: [Int] = []
    private(set) var writes: [(Int, Bool)] = []
    func card(_ mid: Int) async throws -> SpaceCard {
        reads.append(mid)
        if readFails { throw URLError(.cannotConnectToHost) }
        return SpaceCard(mid: mid, isFollowing: following)
    }
    func write(_ mid: Int, _ follows: Bool) async throws {
        writes.append((mid, follows))
        if writeFails { throw URLError(.cannotConnectToHost) }
    }
}

@MainActor
private final class FollowGate<Value: Sendable> {
    private(set) var count = 0
    private var continuations: [Int: CheckedContinuation<Value, any Error>] = [:]
    func load() async throws -> Value {
        count += 1
        let ticket = count
        return try await withCheckedThrowingContinuation { continuations[ticket] = $0 }
    }
    func succeed(_ ticket: Int, _ value: Value) { continuations.removeValue(forKey: ticket)?.resume(returning: value) }
    func fail(_ ticket: Int) { continuations.removeValue(forKey: ticket)?.resume(throwing: URLError(.cannotConnectToHost)) }
}

@main @MainActor
enum LiveRoomFollowRegression {
    static func main() async {
        await permissionsAndLoadedState()
        await readFailureRetryAndWriteRollback()
        await accountGenerationRejectsLateCard()
        await duplicateTapAndLateWriteCannotAffectNewAccount()
        await pendingCardCannotOverwriteFollowMutation()
        await logoutClearsRelationAndRejectsOldWrite()
        print("Live room follow regression passed: permissions, known relation, retry, rollback, account generations, duplicate taps, stale reads/writes, and logout")
    }

    private static func context(mid: Int = 42, loggedIn: Bool = true, accountID: Int = 99) -> LiveRoomFollowModel.Context {
        .init(mid: mid, sessionID: UUID(), isLoggedIn: loggedIn, accountID: loggedIn ? accountID : nil)
    }

    private static func model(_ api: FollowAPI) -> LiveRoomFollowModel {
        LiveRoomFollowModel(cardLoader: { try await api.card($0) }, relationWriter: { try await api.write($0, $1) })
    }

    private static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        preconditionFailure("Injected follow request did not become pending")
    }

    private static func permissionsAndLoadedState() async {
        let api = FollowAPI()
        let model = model(api)
        let current = context()
        let unknown = await model.toggleFollow(current)
        precondition(unknown != nil && api.writes.isEmpty && model.isFollowing == nil)
        let guest = context(loggedIn: false)
        await model.load(guest)
        let guestMessage = await model.toggleFollow(guest)
        precondition(guestMessage == "请先登录" && model.isFollowing == false && api.writes.isEmpty)
        let own = context(accountID: 42)
        await model.load(own)
        let ownMessage = await model.toggleFollow(own)
        precondition(ownMessage == "不能关注自己" && api.writes.isEmpty)
        let invalid = context(mid: 0)
        await model.load(invalid)
        let invalidMessage = await model.toggleFollow(invalid)
        precondition(invalidMessage != nil && !model.isLoading && api.writes.isEmpty)

        await model.load(current)
        precondition(model.isFollowing == true)
        let removed = await model.toggleFollow(current)
        precondition(removed == "已取消关注" && model.isFollowing == false)
        precondition(api.writes.count == 1 && api.writes[0].0 == 42 && !api.writes[0].1,
                     "An existing following relation must issue an unfollow, not another follow")
        let added = await model.toggleFollow(current)
        precondition(added == "已关注" && model.isFollowing == true && api.writes[1].1)
    }

    private static func readFailureRetryAndWriteRollback() async {
        let api = FollowAPI()
        api.readFails = true
        let model = model(api)
        let current = context()
        await model.load(current)
        precondition(model.isFollowing == nil && model.errorMessage != nil && !model.isLoading)
        _ = await model.toggleFollow(current)
        precondition(api.writes.isEmpty, "Unknown relation must never be guessed after a read error")
        api.readFails = false
        await model.load(current, force: true)
        precondition(model.isFollowing == true && model.errorMessage == nil)
        api.writeFails = true
        let message = await model.toggleFollow(current)
        precondition(message != nil && model.isFollowing == true && !model.isToggling,
                     "A failed write restores the previously loaded state")
    }

    private static func accountGenerationRejectsLateCard() async {
        let reads = FollowGate<SpaceCard>()
        let model = LiveRoomFollowModel(cardLoader: { _ in try await reads.load() }, relationWriter: { _, _ in
            preconditionFailure("This scenario does not authorize writes")
        })
        let first = Task { await model.load(context()) }
        await waitUntil { reads.count == 1 }
        let current = Task { await model.load(context(accountID: 100)) }
        await waitUntil { reads.count == 2 }
        reads.succeed(1, SpaceCard(mid: 42, isFollowing: true))
        await first.value
        precondition(model.isFollowing == nil && model.isLoading,
                     "Old cleanup must not end the new account's pending load")
        reads.succeed(2, SpaceCard(mid: 42, isFollowing: false))
        await current.value
        precondition(model.isFollowing == false && !model.isLoading)
    }

    private static func duplicateTapAndLateWriteCannotAffectNewAccount() async {
        let writes = FollowGate<Bool>()
        let model = LiveRoomFollowModel(cardLoader: { mid in SpaceCard(mid: mid, isFollowing: true) },
                                        relationWriter: { _, _ in _ = try await writes.load() })
        let oldAccount = context()
        await model.load(oldAccount)
        let old = Task { await model.toggleFollow(oldAccount) }
        await waitUntil { writes.count == 1 }
        let duplicate = await model.toggleFollow(oldAccount)
        precondition(duplicate == nil && writes.count == 1 && model.isToggling)
        let currentAccount = context(accountID: 100)
        await model.load(currentAccount)
        let current = Task { await model.toggleFollow(currentAccount) }
        await waitUntil { writes.count == 2 }
        writes.fail(1)
        let oldMessage = await old.value
        precondition(oldMessage == nil && model.isFollowing == false && model.isToggling,
                     "A late failure from another account must neither roll back nor finish the current write")
        writes.succeed(2, true)
        let currentMessage = await current.value
        precondition(currentMessage == "已取消关注" && model.isFollowing == false && !model.isToggling)
    }

    private static func pendingCardCannotOverwriteFollowMutation() async {
        let reads = FollowGate<SpaceCard>()
        let writes = FollowGate<Bool>()
        let model = LiveRoomFollowModel(cardLoader: { _ in try await reads.load() },
                                        relationWriter: { _, _ in _ = try await writes.load() })
        let current = context()
        let initial = Task { await model.load(current) }
        await waitUntil { reads.count == 1 }
        reads.succeed(1, SpaceCard(mid: 42, isFollowing: true))
        await initial.value
        let refresh = Task { await model.load(current, force: true) }
        await waitUntil { reads.count == 2 }
        let action = Task { await model.toggleFollow(current) }
        await waitUntil { writes.count == 1 }
        reads.succeed(2, SpaceCard(mid: 42, isFollowing: true))
        await refresh.value
        precondition(model.isFollowing == false && model.isToggling,
                     "A pre-write profile response cannot overwrite the optimistic relation")
        writes.succeed(1, true)
        _ = await action.value
        precondition(model.isFollowing == false && !model.isToggling)
    }

    private static func logoutClearsRelationAndRejectsOldWrite() async {
        let writes = FollowGate<Bool>()
        let model = LiveRoomFollowModel(cardLoader: { mid in SpaceCard(mid: mid, isFollowing: false) },
                                        relationWriter: { _, _ in _ = try await writes.load() })
        let current = context()
        await model.load(current)
        let action = Task { await model.toggleFollow(current) }
        await waitUntil { writes.count == 1 }
        precondition(model.isFollowing == true)
        let guest = context(loggedIn: false)
        await model.load(guest)
        writes.succeed(1, true)
        let message = await action.value
        precondition(message == nil && model.isFollowing == false && !model.isToggling,
                     "A completed old follow must not reappear after logout")
    }
}
