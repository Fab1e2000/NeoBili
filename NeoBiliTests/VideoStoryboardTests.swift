import XCTest
import UIKit
@testable import NeoBili

final class VideoStoryboardTests: XCTestCase {
    func testSentinelTimeBoundaryAndSpriteSheetTransition() throws {
        let json = #"{"img_x_len":2,"img_y_len":2,"img_x_size":160,"img_y_size":90,"image":["//example.com/first.jpg","http://example.com/second.jpg"],"index":[0,0,10,20,30,40,50,60,70]}"#
        let board = try JSONDecoder().decode(VideoStoryboard.self, from: Data(json.utf8))
        XCTAssertEqual(board.tile(at: 0)?.rect, CGRect(x: 0, y: 0, width: 160, height: 90))
        XCTAssertEqual(board.tile(at: 9.9)?.rect.origin.x, 0)
        XCTAssertEqual(board.tile(at: 10)?.rect.origin.x, 160)
        XCTAssertEqual(board.tile(at: 20)?.rect.origin, CGPoint(x: 0, y: 90))
        XCTAssertEqual(board.tile(at: 40)?.url.absoluteString, "https://example.com/second.jpg")
        XCTAssertEqual(board.tile(at: 40)?.rect.origin, .zero)
        XCTAssertEqual(board.tile(at: 999)?.rect, CGRect(x: 160, y: 90, width: 160, height: 90))
        XCTAssertNil(board.tile(at: .nan))
    }

    func testMissingOrInvalidStoryboardsHaveNoPreview() {
        let empty = VideoStoryboard(imgXLen: 0, imgYLen: 0, imgXSize: 0, imgYSize: 0, image: [], index: [])
        XCTAssertNil(empty.tile(at: 15))
        let invalid = VideoStoryboard(imgXLen: 2, imgYLen: 2, imgXSize: 160, imgYSize: 90,
                                      image: ["file:///private/test.jpg"], index: [0, 0, 10])
        XCTAssertNil(invalid.tile(at: 10))
    }
    @MainActor func testWarmFramesAreSynchronousAndReuseMetadataAcrossControlSessions() async throws {
        let board = VideoStoryboard(imgXLen: 2, imgYLen: 2, imgXSize: 16, imgYSize: 9,
                                    image: ["https://example.com/1", "https://example.com/2"],
                                    index: [0, 0, 10, 20, 30, 40, 50, 60, 70])
        var metadataCalls = 0
        var imageCalls = 0
        let store = VideoStoryboardStore(metadataLoader: { _ in metadataCalls += 1; return board },
                                        imageLoader: { _ in
            imageCalls += 1
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: 32, height: 18), format: format).image { context in
                UIColor.red.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 32, height: 18))
            }
        })
        let video = VideoPreviewID(bvid: "test", cid: 1)
        await store.load(video)
        await store.prepare(at: 0)
        XCTAssertEqual(imageCalls, 2) // current and adjacent sheet already warm
        for time in stride(from: 0.0, through: 70.0, by: 1) {
            XCTAssertEqual(store.frame(at: time)?.size, CGSize(width: 16, height: 9))
        }
        await store.load(video) // controls reopen
        await store.prepare(at: 40)
        XCTAssertEqual(metadataCalls, 1)
        XCTAssertEqual(imageCalls, 2)
    }

    @MainActor func testEmptyMetadataAutomaticallyRecoversWithoutReenteringVideo() async {
        var calls = 0
        let board = retryBoard
        let store = VideoStoryboardStore(metadataLoader: { _ in
            calls += 1
            if calls < 3 { return VideoStoryboard(imgXLen: 0, imgYLen: 0, imgXSize: 0, imgYSize: 0, image: [], index: []) }
            return board
        }, retryWait: { _ in })
        await store.load(VideoPreviewID(bvid: "retry", cid: 1))
        XCTAssertEqual(calls, 3)
        XCTAssertFalse(store.failed)
        XCTAssertNotNil(store.storyboard)
    }

    @MainActor func testExhaustedMetadataRetriesAreThrottledAndLaterDragCanRecover() async {
        var calls = 0
        var clock = 10.0
        let board = retryBoard
        let store = VideoStoryboardStore(metadataLoader: { _ in
            calls += 1
            if calls <= 3 { throw URLError(.timedOut) }
            return board
        }, now: { clock }, retryWait: { _ in })
        let video = VideoPreviewID(bvid: "retry", cid: 1)
        await store.load(video)
        XCTAssertTrue(store.failed)
        XCTAssertNil(store.storyboard)
        for _ in 0..<20 { await store.load(video) }
        XCTAssertEqual(calls, 3)
        clock += 3
        await store.load(video)
        XCTAssertEqual(calls, 4)
        XCTAssertFalse(store.failed)
        XCTAssertNotNil(store.storyboard)
    }

    @MainActor func testSpriteFailureRetriesAndRecoversWithinSameVideo() async {
        let board = retryBoard
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 9)).image { $0.fill(CGRect(x: 0, y: 0, width: 16, height: 9)) }
        var calls = 0
        var clock = 10.0
        let store = VideoStoryboardStore(metadataLoader: { _ in board }, imageLoader: { _ in
            calls += 1
            if calls <= 3 { throw URLError(.cannotConnectToHost) }
            return image
        }, now: { clock }, retryWait: { _ in })
        await store.load(VideoPreviewID(bvid: "retry", cid: 1))
        await store.prepare(at: 0)
        XCTAssertEqual(calls, 3)
        XCTAssertNil(store.frame(at: 0))
        XCTAssertEqual(store.failedURLs.count, 1)
        await store.prepare(at: 0)
        XCTAssertEqual(calls, 3)
        clock += 3
        await store.prepare(at: 0)
        XCTAssertEqual(calls, 4)
        XCTAssertNotNil(store.frame(at: 0))
        XCTAssertTrue(store.failedURLs.isEmpty)
    }

    @MainActor func testCancellationDoesNotConsumeThreeNetworkAttempts() async {
        var calls = 0
        let store = VideoStoryboardStore(metadataLoader: { _ in
            calls += 1
            throw CancellationError()
        }, retryWait: { _ in XCTFail("Cancellation must not retry") })
        await store.load(VideoPreviewID(bvid: "cancel", cid: 1))
        XCTAssertEqual(calls, 1)
    }

    private var retryBoard: VideoStoryboard {
        VideoStoryboard(imgXLen: 1, imgYLen: 1, imgXSize: 16, imgYSize: 9,
                        image: ["https://example.com/retry"], index: [0, 0])
    }

}
