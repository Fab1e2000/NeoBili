#if canImport(NeoBiliData)
@testable import NeoBiliData
#endif
#if canImport(NeoBiliDomain)
@testable import NeoBiliDomain
#endif
import XCTest
@testable import NeoBili

@MainActor
final class VideoLikeStateTests: XCTestCase {
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
        let pending = PendingModelResult<VideoRelation>()
        var requests: [Bool] = []
        let model = VideoDetailViewModel(bvid: detail.bvid, likeStore: VideoLikeStore(),
            fetchDetail: { _ in detail }, fetchRelation: { _, _ in await pending.value() },
            sendLike: { _, liked in requests.append(liked) })
        await model.load()
        let first = Task { await model.toggleLike(isLoggedIn: true) }
        await waitForPendingRequest { pending.isWaiting }
        await model.toggleLike(isLoggedIn: true)
        XCTAssertTrue(requests.isEmpty)
        pending.resolve(VideoRelation(attention: false, favorite: false, like: true, dislike: false, coin: 0))
        await first.value
        XCTAssertEqual(requests, [false])
    }

    func testLateLikeFailureCannotOverwriteNewAccountOverride() async throws {
        let likes = VideoLikeStore()
        let pending = PendingModelResult<Bool>()
        let detail = try video()
        let model = VideoDetailViewModel(bvid: detail.bvid, likeStore: likes,
            fetchDetail: { _ in detail }, fetchRelation: { _, _ in self.unlikedRelation },
            sendLike: { _, _ in
                _ = await pending.value()
                throw URLError(.timedOut)
            })
        await model.load()
        let request = Task { await model.toggleLike(isLoggedIn: true) }
        await waitForPendingRequest { pending.isWaiting }
        likes.resetSession()
        likes.setOverride(aid: detail.aid, liked: true)
        pending.resolve(true)
        await request.value
        XCTAssertTrue(likes.isLiked(aid: detail.aid, serverValue: false))
    }

    private var unlikedRelation: VideoRelation {
        VideoRelation(attention: false, favorite: false, like: false, dislike: false, coin: 0)
    }

    private func video() throws -> VideoDetail {
        try decode(#"""
        {"bvid":"BVTest","aid":9,"cid":1,"title":"test","desc":"","pic":"","duration":60,
        "pubdate":1,"owner":{"mid":42,"name":"test","face":""},
        "stat":{"view":1,"danmaku":0,"like":10,"favorite":0,"coin":0,"share":0,"reply":0},"pages":[]}
        """#)
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}
