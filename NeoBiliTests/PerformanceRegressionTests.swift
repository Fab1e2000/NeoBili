import XCTest
import UIKit
@testable import NeoBili

@MainActor
final class PerformanceRegressionTests: XCTestCase {
    private func bitmap(width: Int, height: Int) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func testCardDownsamplingKeepsCropPixelsWithoutDecodingOriginalSize() throws {
        let original = bitmap(width: 2_048, height: 1_536)
        let data = try XCTUnwrap(original.jpegData(compressionQuality: 0.85))
        let target = try XCTUnwrap(ImagePixelSize(points: CGSize(width: 128, height: 128), scale: 3))
        let thumbnail = try XCTUnwrap(ImageDownsampling.decode(data, fitting: target))
        XCTAssertGreaterThanOrEqual(thumbnail.width, target.width)
        XCTAssertGreaterThanOrEqual(thumbnail.height, target.height)
        XCTAssertEqual(thumbnail.width, 512)
        XCTAssertEqual(thumbnail.height, 384)
        XCTAssertLessThan(thumbnail.bytesPerRow * thumbnail.height,
                          try XCTUnwrap(original.cgImage).bytesPerRow * 1_536 / 4)
    }

    func testBitmapCacheHonorsByteBudgetLRUAndReplacement() async throws {
        let image = bitmap(width: 64, height: 64)
        let cgImage = try XCTUnwrap(image.cgImage)
        let cost = cgImage.bytesPerRow * cgImage.height
        let cache = BiliImageCache(maximumBytes: cost * 2, maximumEntries: 20)
        let urls = (0..<3).map { URL(string: "https://example.invalid/bitmap/\($0)")! }
        await cache.insert(image, for: urls[0])
        await cache.insert(image, for: urls[1])
        _ = await cache.cachedImage(for: urls[0])
        await cache.insert(image, for: urls[2])
        let retained = await cache.cachedImage(for: urls[0])
        let evicted = await cache.cachedImage(for: urls[1])
        XCTAssertNotNil(retained, "Recently displayed images must survive an older cache entry")
        XCTAssertNil(evicted)
        await cache.insert(image, for: urls[0])
        let afterReplacement = await cache.cachedByteCount
        XCTAssertEqual(afterReplacement, cost * 2, "Replacing a key must not double-charge its bitmap")
        await cache.insert(bitmap(width: 128, height: 128), for: urls[1])
        let afterOversized = await cache.cachedByteCount
        XCTAssertEqual(afterOversized, cost * 2, "An oversized original must not clear the small-image cache")
    }

    func testConcurrentVisibleCellsShareSingleDecodeTask() async throws {
        let image = bitmap(width: 64, height: 64)
        let calls = ImageRequestProbe(image: image)
        let cache = BiliImageCache()
        let url = URL(string: "https://example.invalid/shared-image")!
        let one = Task { try await cache.image(for: url) { await calls.download() } }
        try await waitUntil { await calls.count == 1 }
        let two = Task { try await cache.image(for: url) { await calls.download() } }
        await calls.release()
        _ = try await one.value
        _ = try await two.value
        let count = await calls.count
        XCTAssertEqual(count, 1)
    }

    func testCancelledQueuedPrefetchExitsAndCancelledDetailSkipsPlaybackRequest() async throws {
        let detail = try JSONDecoder().decode(VideoDetail.self, from: Data(#"""
        {"bvid":"BVTest","aid":9,"cid":1,"title":"test","desc":"","pic":"","duration":60,
        "pubdate":1,"owner":{"mid":42,"name":"test","face":""},
        "stat":{"view":1,"danmaku":0,"like":10,"favorite":0,"coin":0,"share":0,"reply":0},"pages":[]}
        """#.utf8))
        let payload = PlayURLData(quality: 64, acceptQuality: nil, acceptDescription: nil,
                                  durl: nil, dash: nil, vVoucher: nil)
        let calls = PrefetchRequestProbe(detail: detail, playback: payload)
        let cache = VideoPreparationCache(detailLoader: { await calls.detail($0) },
                                         playbackLoader: { bvid, _ in await calls.play(bvid) })
        let one = Task { await cache.prefetch(bvid: "one") }
        let two = Task { await cache.prefetch(bvid: "two") }
        try await waitUntil { await calls.detailCount == 2 }
        let queued = Task {
            await cache.prefetch(bvid: "queued")
            await calls.didFinishQueued()
        }
        try await waitUntil { await cache.queuedPrefetchCount == 1 }
        queued.cancel()
        // The two detail requests are deliberately still suspended here.
        try await waitUntil { await calls.queuedFinished }
        let pendingCount = await cache.queuedPrefetchCount
        XCTAssertEqual(pendingCount, 0)
        one.cancel()
        await calls.release()
        await one.value
        await two.value
        await queued.value
        let playbackIDs = await calls.playbackIDs
        XCTAssertEqual(playbackIDs, ["two"])
        _ = try await cache.detail(for: "one")
        let detailCount = await calls.detailCount
        XCTAssertEqual(detailCount, 2, "Shared detail remains useful when a user later opens the video")
    }

    func testAlreadyCancelledForegroundRequestsDoNotStartNetworkWork() async {
        let requests = CancelledRequestProbe()
        let cache = VideoPreparationCache(detailLoader: { _ in
            await requests.record()
            throw URLError(.cancelled)
        }, playbackLoader: { _, _ in
            await requests.record()
            throw URLError(.cancelled)
        })
        let detail = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try? await cache.detail(for: "cancelled")
        }
        let playback = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try? await cache.playbackURL(bvid: "cancelled", cid: 1)
        }
        await detail.value
        await playback.value
        let count = await requests.count
        XCTAssertEqual(count, 0)
    }

    private func waitUntil(_ condition: @Sendable () async -> Bool) async throws {
        for _ in 0..<400 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw URLError(.timedOut)
    }
}

private actor CancelledRequestProbe {
    private(set) var count = 0
    func record() { count += 1 }
}

private actor ImageRequestProbe {
    let image: UIImage
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var count = 0
    init(image: UIImage) { self.image = image }
    func download() async -> UIImage {
        count += 1
        await withCheckedContinuation { continuation = $0 }
        return image
    }
    func release() { continuation?.resume(); continuation = nil }
}

private actor PrefetchRequestProbe {
    let detailResult: VideoDetail
    let playbackResult: PlayURLData
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var detailCount = 0
    private(set) var playbackIDs: [String] = []
    private(set) var queuedFinished = false
    init(detail: VideoDetail, playback: PlayURLData) {
        detailResult = detail
        playbackResult = playback
    }
    func detail(_ bvid: String) async -> VideoDetail {
        detailCount += 1
        await withCheckedContinuation { continuations.append($0) }
        return detailResult
    }
    func play(_ bvid: String) -> PlayURLData {
        playbackIDs.append(bvid)
        return playbackResult
    }
    func didFinishQueued() { queuedFinished = true }
    func release() {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }
}
