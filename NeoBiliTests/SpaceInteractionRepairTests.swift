#if canImport(NeoBiliDomain)
@testable import NeoBiliDomain
#endif
import XCTest
@testable import NeoBili

@MainActor
final class SpaceInteractionRepairTests: XCTestCase {
    func testSpaceDynamicsUseOnlyTheirInjectedLikeStore() {
        let firstLikes = VideoLikeStore()
        let otherLikes = VideoLikeStore()
        let first = SpaceViewModel(mid: 42, services: services(), likeStore: firstLikes)
        let other = SpaceViewModel(mid: 42, services: services(), likeStore: otherLikes)
        let video = FollowedVideo(id: "fixture", bvid: "BVfixture", aid: 17, title: "Fixture",
            cover: "", durationText: "1:00", playText: "0", authorMid: 42,
            authorName: "Fixture", authorFace: "", publishedText: "")
        let entry = DynamicEntry(id: "fixture", authorMid: 42, authorName: "Fixture", authorFace: "",
            publishedText: "", text: "", images: [], video: video, likeCount: 3,
            commentCount: 0, forwardCount: 0, isLikedByServer: false, commentOid: 17, commentType: 1)
        firstLikes.setOverride(aid: 17, liked: true)
        XCTAssertTrue(first.dynamics.isLiked(entry))
        XCTAssertEqual(first.dynamics.likeCount(entry), 4)
        XCTAssertFalse(other.dynamics.isLiked(entry))
        XCTAssertEqual(other.dynamics.likeCount(entry), 3)
        firstLikes.resetSession()
        XCTAssertFalse(first.dynamics.isLiked(entry))
    }

    func testOlderCardReadCannotUndoSuccessfulFollow() async throws {
        let gate = SpaceRepairGate<SpaceCard>()
        defer { Task { await gate.cancelAll() } }
        let writes = SpaceRepairWrites()
        var services = services()
        services.community.spaceProfileOperation = { _ in try await gate.load() }
        services.video.modifyRelationOperation = { mid, follow in await writes.append(mid, follow) }
        let model = SpaceViewModel(mid: 42, services: services)
        let context = context()
        let first = Task { await model.loadCard(context) }
        try await waitUntil { await gate.count == 1 }
        await gate.resolve(1, Self.card(following: false))
        await first.value
        let stale = Task { await model.loadCard(context) }
        try await waitUntil { await gate.count == 2 }
        let message = await model.toggleFollow(context)
        XCTAssertEqual(message, "已关注")
        await gate.resolve(2, Self.card(following: false))
        await stale.value
        XCTAssertEqual(model.isFollowing, true)
        let mutations = await writes.values
        XCTAssertEqual(mutations, [true])
    }

    func testUnknownAndFailedRelationCannotWriteAndRetryLoadsUnfollowDirection() async throws {
        let gate = SpaceRepairGate<SpaceCard>()
        defer { Task { await gate.cancelAll() } }
        let writes = SpaceRepairWrites()
        var services = services()
        services.community.spaceProfileOperation = { _ in try await gate.load() }
        services.video.modifyRelationOperation = { mid, follow in await writes.append(mid, follow) }
        let model = SpaceViewModel(mid: 42, services: services)
        let context = context()
        let unknown = await model.toggleFollow(context)
        XCTAssertEqual(unknown, "关注状态尚未加载，请重试")
        let first = Task { await model.loadCard(context) }
        try await waitUntil { await gate.count == 1 }
        await gate.fail(1)
        await first.value
        XCTAssertNil(model.isFollowing)
        XCTAssertNotNil(model.followError)
        _ = await model.toggleFollow(context)
        var mutations = await writes.values
        XCTAssertTrue(mutations.isEmpty)
        let retry = Task { await model.loadCard(context) }
        try await waitUntil { await gate.count == 2 }
        await gate.resolve(2, Self.card(following: true))
        await retry.value
        XCTAssertNil(model.followError)
        _ = await model.toggleFollow(context)
        mutations = await writes.values
        XCTAssertEqual(mutations, [false])
    }

    func testFailedWriteRestoresKnownFollowState() async {
        let card = Self.card(following: true)
        var services = services()
        services.community.spaceProfileOperation = { _ in card }
        services.video.modifyRelationOperation = { _, _ in throw URLError(.cannotConnectToHost) }
        let model = SpaceViewModel(mid: 42, services: services)
        let context = context()
        await model.loadCard(context)
        let message = await model.toggleFollow(context)
        XCTAssertNotNil(message)
        XCTAssertEqual(model.isFollowing, true)
        XCTAssertFalse(model.isTogglingFollow)
    }

    func testSelfAndGuestCannotWrite() async {
        let card = Self.card(following: false)
        var services = services()
        services.community.spaceProfileOperation = { _ in card }
        services.video.modifyRelationOperation = { _, _ in XCTFail("Self/guest cannot mutate relation") }
        let model = SpaceViewModel(mid: 42, services: services)
        let own = context(accountID: 42)
        await model.loadCard(own)
        XCTAssertTrue(model.isOwnAccount(own))
        let ownMessage = await model.toggleFollow(own)
        XCTAssertEqual(ownMessage, "不能关注自己")
        let guest = context(loggedIn: false)
        await model.loadCard(guest)
        let guestMessage = await model.toggleFollow(guest)
        XCTAssertEqual(guestMessage, "请先登录")
    }

    func testAccountSwitchRejectsLateReadAndOldWriteFailure() async throws {
        let cards = SpaceRepairGate<SpaceCard>()
        let writes = SpaceRepairGate<Bool>()
        defer { Task { await cards.cancelAll(); await writes.cancelAll() } }
        var services = services()
        services.community.spaceProfileOperation = { _ in try await cards.load() }
        services.video.modifyRelationOperation = { _, _ in _ = try await writes.load() }
        let model = SpaceViewModel(mid: 42, services: services)
        let oldContext = context()
        let initial = Task { await model.loadCard(oldContext) }
        try await waitUntil { await cards.count == 1 }
        await cards.resolve(1, Self.card(following: true))
        await initial.value
        let stale = Task { await model.loadCard(oldContext) }
        try await waitUntil { await cards.count == 2 }
        let write = Task { await model.toggleFollow(oldContext) }
        try await waitUntil { await writes.count == 1 }
        let nextContext = context(accountID: 100)
        model.setFollowContext(nextContext)
        XCTAssertNil(model.isFollowing)
        await cards.resolve(2, Self.card(following: true))
        await writes.fail(1)
        await stale.value
        _ = await write.value
        XCTAssertNil(model.isFollowing)
        XCTAssertFalse(model.isTogglingFollow)
        let fresh = Task { await model.loadCard(nextContext) }
        try await waitUntil { await cards.count == 3 }
        await cards.resolve(3, Self.card(following: false))
        await fresh.value
        XCTAssertEqual(model.isFollowing, false)
    }

    func testFirstVideoPageFailureCanRetryInPlace() async throws {
        let gate = SpaceRepairGate<SpaceVideoPage>()
        defer { Task { await gate.cancelAll() } }
        var services = services()
        services.community.spaceVideosOperation = { _, page in
            XCTAssertEqual(page, 1)
            return try await gate.load()
        }
        let model = SpaceViewModel(mid: 42, services: services)
        let initial = Task { await model.loadVideosIfNeeded() }
        try await waitUntil { await gate.count == 1 }
        await gate.fail(1)
        await initial.value
        XCTAssertNotNil(model.videosError)
        XCTAssertFalse(model.isLoadingVideos)
        let response = try JSONDecoder().decode(SpaceVideoPage.self, from: Data(
            #"{"list":{"vlist":[{"bvid":"BVRetry","title":"Recovered"}]},"page":{"count":1}}"#.utf8))
        let retry = Task { await model.reloadVideos() }
        try await waitUntil { await gate.count == 2 }
        await gate.resolve(2, response)
        await retry.value
        XCTAssertNil(model.videosError)
        XCTAssertEqual(model.videos.map(\.bvid), ["BVRetry"])
        XCTAssertEqual(model.videosGeneration, 1)
    }

    func testRefreshingFirstPageRejectsLateOldPagination() async throws {
        let gate = SpaceRepairGate<SpaceVideoPage>()
        defer { Task { await gate.cancelAll() } }
        var services = services()
        services.community.spaceVideosOperation = { _, _ in try await gate.load() }
        let model = SpaceViewModel(mid: 42, services: services)
        func page(_ bvid: String, total: Int) throws -> SpaceVideoPage {
            try JSONDecoder().decode(SpaceVideoPage.self, from: Data(
                "{\"list\":{\"vlist\":[{\"bvid\":\"\(bvid)\"}]},\"page\":{\"count\":\(total)}}".utf8))
        }
        let initial = Task { await model.reloadVideos() }
        try await waitUntil { await gate.count == 1 }
        await gate.resolve(1, try page("BVFirst", total: 2))
        await initial.value
        let oldPage = Task { await model.loadReplacementPage() }
        try await waitUntil { await gate.count == 2 }
        let refresh = Task { await model.reloadVideos() }
        try await waitUntil { await gate.count == 3 }
        await gate.resolve(3, try page("BVFresh", total: 1))
        await refresh.value
        await gate.resolve(2, try page("BVOldPage", total: 2))
        await oldPage.value
        XCTAssertEqual(model.videos.map(\.bvid), ["BVFresh"])
        XCTAssertFalse(model.isLoadingMoreVideos)
    }

    func testFailedRefreshPreservesContentAndPaginationAndRetryRecovers() async throws {
        let gate = SpaceRepairGate<SpaceVideoPage>()
        defer { Task { await gate.cancelAll() } }
        var services = services()
        services.community.spaceVideosOperation = { _, page in try await gate.load(page) }
        let model = SpaceViewModel(mid: 42, services: services)
        func page(_ bvid: String, total: Int) throws -> SpaceVideoPage {
            try JSONDecoder().decode(SpaceVideoPage.self, from: Data(
                "{\"list\":{\"vlist\":[{\"bvid\":\"\(bvid)\"}]},\"page\":{\"count\":\(total)}}".utf8))
        }
        let initial = Task { await model.reloadVideos() }
        try await waitUntil { await gate.count == 1 }
        await gate.resolve(1, try page("BVFirst", total: 4))
        await initial.value
        let secondPage = Task { await model.loadReplacementPage() }
        try await waitUntil { await gate.count == 2 }
        await gate.resolve(2, try page("BVSecond", total: 4))
        await secondPage.value
        let refresh = Task { await model.reloadVideos() }
        try await waitUntil { await gate.count == 3 }
        await gate.fail(3)
        await refresh.value
        XCTAssertNotNil(model.videosError)
        XCTAssertEqual(model.videos.map(\.bvid), ["BVFirst", "BVSecond"])
        XCTAssertEqual(model.videosGeneration, 1)
        let thirdPage = Task { await model.loadReplacementPage() }
        try await waitUntil { await gate.count == 4 }
        await gate.resolve(4, try page("BVThird", total: 4))
        await thirdPage.value
        XCTAssertEqual(model.videos.map(\.bvid), ["BVFirst", "BVSecond", "BVThird"])
        let retry = Task { await model.reloadVideos() }
        try await waitUntil { await gate.count == 5 }
        await gate.resolve(5, try page("BVFresh", total: 1))
        await retry.value
        XCTAssertNil(model.videosError)
        XCTAssertEqual(model.videos.map(\.bvid), ["BVFresh"])
        XCTAssertEqual(model.videosGeneration, 2)
        let requests = await gate.pages
        XCTAssertEqual(requests, [1, 2, 1, 3, 1])
    }

    func testStagedVideosRefreshKeepsOldListUntilCommitAndFailureKeepsItToo() async throws {
        let gate = SpaceRepairGate<SpaceVideoPage>()
        defer { Task { await gate.cancelAll() } }
        var services = services()
        services.community.spaceVideosOperation = { _, page in try await gate.load(page) }
        let model = SpaceViewModel(mid: 42, services: services)
        func page(_ bvid: String) throws -> SpaceVideoPage {
            try JSONDecoder().decode(SpaceVideoPage.self, from: Data(
                "{\"list\":{\"vlist\":[{\"bvid\":\"\(bvid)\"}]},\"page\":{\"count\":1}}".utf8))
        }
        let initial = Task { await model.reloadVideos() }
        try await waitUntil { await gate.count == 1 }
        await gate.resolve(1, try page("BVOld"))
        await initial.value
        XCTAssertEqual(model.videosGeneration, 1)

        let staging = Task { await model.stageVideosRefresh() }
        try await waitUntil { await gate.count == 2 }
        XCTAssertEqual(model.videos.map(\.bvid), ["BVOld"], "the old list stays while the request is in flight")
        await gate.resolve(2, try page("BVNew"))
        let staged = await staging.value
        XCTAssertTrue(staged)
        XCTAssertEqual(model.videos.map(\.bvid), ["BVOld"], "the old list stays until the fade-out ends")
        model.commitVideosRefresh()
        XCTAssertEqual(model.videos.map(\.bvid), ["BVNew"])
        XCTAssertEqual(model.videosGeneration, 2)

        let failing = Task { await model.stageVideosRefresh() }
        try await waitUntil { await gate.count == 3 }
        await gate.fail(3)
        let failed = await failing.value
        XCTAssertFalse(failed)
        model.commitVideosRefresh()
        XCTAssertEqual(model.videos.map(\.bvid), ["BVNew"])
        XCTAssertNotNil(model.videosError)
    }

    private func services() -> ApplicationServices {
        let sessionID = UUID()
        return ApplicationServices(session: .init(currentID: { sessionID }, homeAccount: {
            .init(accountID: 99, hasAppCredential: false)
        }))
    }

    private func context(loggedIn: Bool = true, accountID: Int = 99) -> SpaceViewModel.FollowContext {
        .init(sessionID: UUID(), isLoggedIn: loggedIn, accountID: loggedIn ? accountID : nil)
    }

    private nonisolated static func card(following: Bool) -> SpaceCard {
        SpaceCard(mid: 42, name: "UP", face: "", sign: "", level: 6, isVIP: false,
                  banner: nil, follower: 10, followingCount: 2, likeCount: 20,
                  archiveCount: 1, isFollowing: following)
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Injected request did not start")
        throw CancellationError()
    }
}

private actor SpaceRepairWrites {
    private(set) var values: [Bool] = []
    func append(_ mid: Int, _ follow: Bool) { values.append(follow) }
}

private actor SpaceRepairGate<Value: Sendable> {
    private(set) var count = 0
    private(set) var pages: [Int] = []
    private var continuations: [Int: CheckedContinuation<Value, any Error>] = [:]
    func load(_ page: Int? = nil) async throws -> Value {
        if let page { pages.append(page) }
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
