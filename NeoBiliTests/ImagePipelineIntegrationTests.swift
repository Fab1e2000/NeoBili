import NeoBiliCore
import Synchronization
import UIKit
import XCTest
@testable import NeoBili

private final class ReleaseProbe: Sendable {
    private let onRelease: @Sendable () -> Void

    init(_ onRelease: @escaping @Sendable () -> Void) {
        self.onRelease = onRelease
    }

    deinit { onRelease() }
}

@MainActor
final class ImagePipelineIntegrationTests: XCTestCase {
    private let notifications = NotificationCenter()
    private lazy var pipeline = BiliImagePipeline(cache: BiliImageCache(notifications: notifications), download: { _ in throw URLError(.notConnectedToInternet) })

    func testReplacementEvictionAndClearReleaseValuesAfterUnlocking() {
        let cache = ImageMemoryCache<Int, ReleaseProbe>(maximumBytes: 1, maximumEntries: 1)
        let results = Mutex<[Bool]>([])
        func probe() -> ReleaseProbe {
            ReleaseProbe { [weak cache] in
                guard let cache else { return }
                let read = DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    _ = cache.cachedByteCount
                    read.signal()
                }
                let unlocked = read.wait(timeout: .now() + 1) == .success
                results.withLock { $0.append(unlocked) }
            }
        }
        cache.insert(probe(), for: 1, cost: 1)
        cache.insert(probe(), for: 1, cost: 1)
        cache.insert(probe(), for: 2, cost: 1)
        cache.removeAll()
        XCTAssertEqual(results.withLock { $0 }, [true, true, true])
    }

    func testSynchronousAndAsyncCachesHaveOneOwnerAndMemoryWarningClearsBoth() async throws {
        let url = URL(string: "https://example.invalid/image-cache-\(UUID()).png")!
        let pixels = try XCTUnwrap(ImagePixelSize(points: CGSize(width: 32, height: 32), scale: 1))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        BiliImageMemoryCache.insert(image, for: url, pixelSize: pixels, pipeline: pipeline)
        let loaded = try await pipeline.cache.image(for: url, pixelSize: pixels) {
            XCTFail("A synchronous cache hit must also satisfy the async loader without another decode")
            throw URLError(.badServerResponse)
        }
        XCTAssertTrue(loaded === image)
        XCTAssertTrue(BiliImageMemoryCache.image(for: url, pixelSize: pixels, pipeline: pipeline) === image)

        notifications.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        XCTAssertNil(BiliImageMemoryCache.image(for: url, pixelSize: pixels, pipeline: pipeline), "Memory pressure must clear the UI lookup too")
        XCTAssertNil(pipeline.cache.cachedImage(for: url, pixelSize: pixels))
    }

    func testIndependentPipelinesDoNotShareBitmapsOrMemoryWarnings() throws {
        let otherNotifications = NotificationCenter()
        let other = BiliImagePipeline(cache: BiliImageCache(notifications: otherNotifications),
                                      download: { _ in throw URLError(.notConnectedToInternet) })
        let url = URL(string: "https://example.invalid/same-image.png")!
        let pixels = try XCTUnwrap(ImagePixelSize(points: CGSize(width: 16, height: 16), scale: 1))
        let first = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { _ in }
        let second = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { _ in }
        BiliImageMemoryCache.insert(first, for: url, pixelSize: pixels, pipeline: pipeline)
        XCTAssertNil(BiliImageMemoryCache.image(for: url, pixelSize: pixels, pipeline: other))
        BiliImageMemoryCache.insert(second, for: url, pixelSize: pixels, pipeline: other)
        notifications.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        XCTAssertNil(BiliImageMemoryCache.image(for: url, pixelSize: pixels, pipeline: pipeline))
        XCTAssertTrue(BiliImageMemoryCache.image(for: url, pixelSize: pixels, pipeline: other) === second)
    }

    func testLocalArtworkUsesSizedCacheWithoutNetwork() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let original = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 512), format: format).image { _ in }
        try XCTUnwrap(original.pngData()).write(to: url)
        let pixels = try XCTUnwrap(ImagePixelSize(points: CGSize(width: 128, height: 64), scale: 1))

        let loaded = try await BiliImageLoader.load(url, pixelSize: pixels, pipeline: pipeline)

        XCTAssertEqual(loaded.cgImage?.width, 128)
        XCTAssertEqual(loaded.cgImage?.height, 64)
        XCTAssertTrue(BiliImageMemoryCache.image(for: url, pixelSize: pixels, pipeline: pipeline) === loaded)
    }

    func testPreloadedOriginalCanBeReadSynchronouslyWithoutDuplicatingBitmap() throws {
        let url = URL(string: "https://example.invalid/image-original-\(UUID()).png")!
        let pixels = try XCTUnwrap(ImagePixelSize(points: CGSize(width: 16, height: 16), scale: 1))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { _ in }
        pipeline.cache.insert(image, for: url)
        XCTAssertTrue(BiliImageMemoryCache.image(for: url, pixelSize: pixels, pipeline: pipeline) === image)
        XCTAssertNil(pipeline.cache.cachedImage(for: url, pixelSize: pixels),
                     "An original should not be charged again under every smaller display size")
    }
}
