import XCTest
@testable import NeoBili

@MainActor
final class VideoActionStateRepairTests: XCTestCase {
    func testRemovingOneOfTwoFoldersKeepsFavoriteAndCount() async throws {
        let calls = ActionCalls()
        let model = try await model(favorited: true, calls: calls)
        await model.updateFavorites(add: [], remove: [1], willBeFavorited: true, isLoggedIn: true)
        XCTAssertEqual(model.relation?.isFavorited, true)
        XCTAssertEqual(model.favoriteCount, 5)
        XCTAssertEqual(model.actionMessage, String(localized: "已收藏"))
        let request = await calls.favoriteRequests.first
        XCTAssertEqual(request?.add, [])
        XCTAssertEqual(request?.remove, [1])
        XCTAssertNotNil(request?.session)
    }

    func testRemovingLastFolderClearsFavoriteOnce() async throws {
        let model = try await model(favorited: true)
        await model.updateFavorites(add: [], remove: [1, 2], willBeFavorited: false, isLoggedIn: true)
        XCTAssertEqual(model.relation?.isFavorited, false)
        XCTAssertEqual(model.favoriteCount, 4)
        XCTAssertEqual(model.actionMessage, String(localized: "已取消收藏"))
    }

    func testAddingMultipleFoldersCountsVideoOnce() async throws {
        let model = try await model(favorited: false)
        await model.updateFavorites(add: [1, 2], remove: [], willBeFavorited: true, isLoggedIn: true)
        XCTAssertEqual(model.relation?.isFavorited, true)
        XCTAssertEqual(model.favoriteCount, 6)
    }

    func testFavoriteFailureRestoresPreviousRelationshipAndCount() async throws {
        let calls = ActionCalls(fails: true)
        let model = try await model(favorited: true, calls: calls)
        await model.updateFavorites(add: [], remove: [1], willBeFavorited: false, isLoggedIn: true)
        XCTAssertEqual(model.relation?.isFavorited, true)
        XCTAssertEqual(model.favoriteCount, 5)
        XCTAssertNotNil(model.actionMessage)
    }

    func testFavoritePendingWriteBlocksOtherActionsAndReleasesAfterCompletion() async throws {
        let calls = ActionCalls(holdFavorite: true)
        let model = try await model(favorited: true, calls: calls)
        let write = Task {
            await model.updateFavorites(add: [], remove: [1], willBeFavorited: true, isLoggedIn: true)
        }
        for _ in 0..<1000 {
            if await calls.isWaiting { break }
            await Task.yield()
        }
        let waiting = await calls.isWaiting
        XCTAssertTrue(waiting)
        await model.updateFavorites(add: [], remove: [2], willBeFavorited: false, isLoggedIn: true)
        await model.tripleAction(isLoggedIn: true)
        let favorites = await calls.favoriteRequests
        let triples = await calls.tripleRequests
        XCTAssertEqual(favorites.count, 1)
        XCTAssertEqual(triples, 0)
        await calls.releaseFavorite()
        await write.value
        await model.tripleAction(isLoggedIn: true)
        let completedTriples = await calls.tripleRequests
        XCTAssertEqual(completedTriples, 1)
    }

    func testTripleSuccessfulLikeClearsDislikeEvenWithPartialSuccess() async throws {
        let calls = ActionCalls(result: TripleResult(like: true, coin: false, fav: true, multiply: 0))
        let model = try await model(disliked: true, calls: calls)
        await model.tripleAction(isLoggedIn: true)
        XCTAssertTrue(model.displayedIsLiked)
        XCTAssertEqual(model.relation?.isDisliked, false)
        XCTAssertEqual(model.relation?.isCoined, false)
        XCTAssertEqual(model.relation?.isFavorited, true)
        XCTAssertEqual(model.likeCount, 11)
    }

    func testTripleFailedLikeKeepsDislikeWhileApplyingOtherSuccesses() async throws {
        let calls = ActionCalls(result: TripleResult(like: false, coin: true, fav: true, multiply: 1))
        let model = try await model(disliked: true, calls: calls)
        await model.tripleAction(isLoggedIn: true)
        XCTAssertFalse(model.displayedIsLiked)
        XCTAssertEqual(model.relation?.isDisliked, true)
        XCTAssertEqual(model.relation?.isCoined, true)
        XCTAssertEqual(model.relation?.isFavorited, true)
        XCTAssertEqual(model.likeCount, 10)
    }

    func testTripleRequestFailurePreservesRelationshipAndCounts() async throws {
        let model = try await model(disliked: true, calls: ActionCalls(fails: true))
        await model.tripleAction(isLoggedIn: true)
        XCTAssertFalse(model.displayedIsLiked)
        XCTAssertEqual(model.relation?.isDisliked, true)
        XCTAssertEqual(model.relation?.isCoined, false)
        XCTAssertEqual(model.likeCount, 10)
        XCTAssertEqual(model.favoriteCount, 5)
        XCTAssertNotNil(model.actionMessage)
    }

    private func model(favorited: Bool = false, disliked: Bool = false,
                       calls: ActionCalls = ActionCalls()) async throws -> VideoDetailViewModel {
        let generation = UUID()
        var services = ApplicationServices(session: SessionService(currentID: { generation },
            homeAccount: { HomeFeedAccount(accountID: 42, hasAppCredential: true) }))
        services.video.updateFavoritesOperation = { _, add, remove, session in
            try await calls.updateFavorites(add: add, remove: remove, session: session)
        }
        services.video.tripleActionOperation = { _, _, _ in try await calls.triple() }
        let detail = try JSONDecoder().decode(VideoDetail.self, from: Data(#"""
        {"bvid":"BVTest","aid":9,"cid":1,"title":"test","desc":"","pic":"","duration":60,
        "pubdate":1,"owner":{"mid":42,"name":"test","face":""},
        "stat":{"view":1,"danmaku":0,"like":10,"favorite":5,"coin":0,"share":0,"reply":0},"pages":[]}
        """#.utf8))
        let relation = VideoRelation(attention: false, favorite: favorited, like: false, dislike: disliked, coin: 0)
        let model = VideoDetailViewModel(bvid: detail.bvid, likeStore: VideoLikeStore(), services: services,
            fetchDetail: { _ in detail }, fetchRelation: { _, _ in relation })
        await model.load()
        return model
    }
}

private actor ActionCalls {
    struct FavoriteRequest: Sendable {
        let add: [Int]
        let remove: [Int]
        let session: UUID?
    }
    private(set) var favoriteRequests: [FavoriteRequest] = []
    private(set) var tripleRequests = 0
    private let fails: Bool
    private let result: TripleResult
    private let holdFavorite: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { continuation != nil }

    init(fails: Bool = false, result: TripleResult = TripleResult(like: true, coin: true, fav: true, multiply: 1),
         holdFavorite: Bool = false) {
        self.fails = fails
        self.result = result
        self.holdFavorite = holdFavorite
    }

    func updateFavorites(add: [Int], remove: [Int], session: UUID?) async throws {
        favoriteRequests.append(FavoriteRequest(add: add, remove: remove, session: session))
        if holdFavorite { await withCheckedContinuation { continuation = $0 } }
        if fails { throw URLError(.timedOut) }
    }

    func releaseFavorite() {
        continuation?.resume()
        continuation = nil
    }

    func triple() throws -> TripleResult {
        tripleRequests += 1
        if fails { throw URLError(.timedOut) }
        return result
    }
}
