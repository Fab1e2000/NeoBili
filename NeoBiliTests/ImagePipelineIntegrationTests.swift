import UIKit
import XCTest
@testable import NeoBili

@MainActor
final class ImagePipelineIntegrationTests: XCTestCase {
    func testSynchronousAndAsyncCachesHaveOneOwnerAndMemoryWarningClearsBoth() async throws {
        let url = URL(string: "https://example.invalid/image-cache-\(UUID()).png")!
        let pixels = try XCTUnwrap(ImagePixelSize(points: CGSize(width: 32, height: 32), scale: 1))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        BiliImageMemoryCache.insert(image, for: url, pixelSize: pixels)
        let loaded = try await BiliImageCache.shared.image(for: url, pixelSize: pixels) {
            XCTFail("A synchronous cache hit must also satisfy the async loader without another decode")
            throw URLError(.badServerResponse)
        }
        XCTAssertTrue(loaded === image)
        XCTAssertTrue(BiliImageMemoryCache.image(for: url, pixelSize: pixels) === image)

        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        XCTAssertNil(BiliImageMemoryCache.image(for: url, pixelSize: pixels), "Memory pressure must clear the UI lookup too")
        XCTAssertNil(BiliImageCache.shared.cachedImage(for: url, pixelSize: pixels))
    }

    func testPreloadedOriginalCanBeReadSynchronouslyWithoutDuplicatingBitmap() throws {
        let url = URL(string: "https://example.invalid/image-original-\(UUID()).png")!
        let pixels = try XCTUnwrap(ImagePixelSize(points: CGSize(width: 16, height: 16), scale: 1))
        let image = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { _ in }
        BiliImageCache.shared.insert(image, for: url)
        XCTAssertTrue(BiliImageMemoryCache.image(for: url, pixelSize: pixels) === image)
        XCTAssertNil(BiliImageCache.shared.cachedImage(for: url, pixelSize: pixels),
                     "An original should not be charged again under every smaller display size")
    }
}
