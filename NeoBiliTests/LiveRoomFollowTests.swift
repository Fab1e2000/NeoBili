import XCTest
@testable import NeoBili

@MainActor
final class LiveRoomFollowTests: XCTestCase {
    func testExistingFollowStateIsLoadedBeforeAnUnfollowWrite() async {
        let card = Self.card(following: true)
        let writes = LiveFollowWrites()
        let model = LiveRoomFollowModel(cardLoader: { _ in card }, relationWriter: { mid, follows in
            await writes.append(mid: mid, follows: follows)
        })
        let context = context()
        await model.load(context)
        XCTAssertEqual(model.isFollowing, true)
        let message = await model.toggleFollow(context)
        XCTAssertEqual(message, "已取消关注")
        let values = await writes.values
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.first?.mid, 42)
        XCTAssertEqual(values.first?.follows, false)
        XCTAssertEqual(model.isFollowing, false)
    }

    func testGuestUnknownAndOwnAccountCannotWrite() async {
        let card = Self.card(following: false)
        let model = LiveRoomFollowModel(cardLoader: { _ in card }, relationWriter: { _, _ in
            XCTFail("No relation mutation is authorized in these states")
        })
        let unknown = context()
        let unknownMessage = await model.toggleFollow(unknown)
        XCTAssertEqual(unknownMessage, "关注状态尚未加载，请重试")
        let guest = context(loggedIn: false)
        await model.load(guest)
        let guestMessage = await model.toggleFollow(guest)
        XCTAssertEqual(guestMessage, "请先登录")
        let own = context(accountID: 42)
        await model.load(own)
        let ownMessage = await model.toggleFollow(own)
        XCTAssertEqual(ownMessage, "不能关注自己")
    }

    func testFailedWriteRestoresLoadedState() async {
        let card = Self.card(following: true)
        let model = LiveRoomFollowModel(cardLoader: { _ in card }, relationWriter: { _, _ in
            throw URLError(.cannotConnectToHost)
        })
        let context = context()
        await model.load(context)
        let message = await model.toggleFollow(context)
        XCTAssertNotNil(message)
        XCTAssertEqual(model.isFollowing, true)
        XCTAssertFalse(model.isToggling)
    }

    func testAccountChangeRejectsLateCardResponse() async throws {
        let pending = LiveFollowGate<SpaceCard>()
        defer { Task { await pending.cancelAll() } }
        let model = LiveRoomFollowModel(cardLoader: { _ in try await pending.load() }, relationWriter: { _, _ in })
        let oldContext = context()
        let old = Task { await model.load(oldContext) }
        try await waitUntil { await pending.count == 1 }
        let freshContext = context()
        let fresh = Task { await model.load(freshContext) }
        try await waitUntil { await pending.count == 2 }
        await pending.resolve(1, Self.card(following: true))
        await old.value
        XCTAssertNil(model.isFollowing, "Previous account relation must never appear for the new account")
        await pending.resolve(2, Self.card(following: false))
        await fresh.value
        XCTAssertEqual(model.isFollowing, false)
    }

    func testRepeatedTapIsIgnoredAndOldWriteCannotRestoreLoggedOutState() async throws {
        let pending = LiveFollowGate<Bool>()
        defer { Task { await pending.cancelAll() } }
        let card = Self.card(following: true)
        let model = LiveRoomFollowModel(cardLoader: { _ in card }, relationWriter: { _, _ in
            _ = try await pending.load()
        })
        let context = context()
        await model.load(context)
        let action = Task { await model.toggleFollow(context) }
        try await waitUntil { await pending.count == 1 }
        let duplicateMessage = await model.toggleFollow(context)
        XCTAssertNil(duplicateMessage)
        XCTAssertTrue(model.isToggling)
        let guest = self.context(loggedIn: false)
        await model.load(guest)
        await pending.fail(1)
        _ = await action.value
        XCTAssertEqual(model.isFollowing, false)
        XCTAssertFalse(model.isToggling)
    }

    func testLiveDescriptionRemovesMarkupWithoutLosingParagraphBreaks() {
        XCTAssertEqual(LiveRoomText.readable("<p>欢迎</p><br/>一起听歌 &amp; 聊天"), "欢迎\n一起听歌 & 聊天")
        XCTAssertNil(LiveRoomText.readable(" <br> "))
    }

    private func context(loggedIn: Bool = true, accountID: Int = 99) -> LiveRoomFollowModel.Context {
        .init(mid: 42, sessionID: UUID(), isLoggedIn: loggedIn, accountID: loggedIn ? accountID : nil)
    }

    private nonisolated static func card(following: Bool) -> SpaceCard {
        SpaceCard(mid: 42, name: "测试主播", face: "", sign: "", level: 6, isVIP: false,
                  banner: nil, follower: 12_345, followingCount: 9, likeCount: 123,
                  archiveCount: 86, isFollowing: following)
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Injected follow request did not become pending")
        throw CancellationError()
    }
}

private actor LiveFollowWrites {
    struct Write: Sendable { let mid: Int; let follows: Bool }
    private(set) var values: [Write] = []
    func append(mid: Int, follows: Bool) { values.append(Write(mid: mid, follows: follows)) }
}

private actor LiveFollowGate<Value: Sendable> {
    private(set) var count = 0
    private var continuations: [Int: CheckedContinuation<Value, any Error>] = [:]
    func load() async throws -> Value {
        count += 1
        let id = count
        return try await withCheckedThrowingContinuation { continuations[id] = $0 }
    }
    func resolve(_ id: Int, _ value: Value) { continuations.removeValue(forKey: id)?.resume(returning: value) }
    func fail(_ id: Int) { continuations.removeValue(forKey: id)?.resume(throwing: URLError(.cannotConnectToHost)) }
    func cancelAll() {
        let pending = Array(continuations.values)
        continuations.removeAll()
        for continuation in pending { continuation.resume(throwing: CancellationError()) }
    }
}
