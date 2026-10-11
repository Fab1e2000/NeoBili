import XCTest
import UIKit
import ImageIO
@testable import NeoBili

@MainActor
final class ImageDecodeRecoveryTests: XCTestCase {
    func testOriginalDecodeFailurePreservesPreviewAndRedownloadsSameURL() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = ImageViewerModel(images: [fixture.image], cache: fixture.cache)
        await model.load(0)
        let preview = try XCTUnwrap(model.previews[0])
        await model.loadOriginal(0)
        let broken = try XCTUnwrap(model.originals[0])
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(broken as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 1, "仅检查文件头/帧数不能保证像素可解码")
        await assertCannotDecode(broken)
        await model.decodingFailed(0, file: broken)
        XCTAssertEqual(model.files[0], preview)
        XCTAssertTrue(model.originalFailures.contains(0))
        XCTAssertTrue(model.canLoadOriginal(0))
        XCTAssertFalse(FileManager.default.fileExists(atPath: broken.path))
        await model.loadOriginal(0)
        let recovered = try XCTUnwrap(model.originals[0])
        let frames = try await ViewerImageFrames(file: recovered)
        let frame = try await frames.frame(0)
        XCTAssertGreaterThan(frame.image.width, 0)
        XCTAssertFalse(model.originalFailures.contains(0))
        let count = await fixture.download.count(for: fixture.image.originalURL!)
        XCTAssertEqual(count, 2)
    }

    func testBaseDecodeFailureInvalidatesCacheBeforeRetry() async throws {
        let fixture = try makeFixture(baseFails: true)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = ImageViewerModel(images: [fixture.image], cache: fixture.cache)
        await model.load(0)
        let broken = try XCTUnwrap(model.previews[0])
        await assertCannotDecode(broken)
        await model.decodingFailed(0, file: broken)
        XCTAssertNil(model.files[0])
        XCTAssertTrue(model.failures.contains(0))
        await model.load(0, retry: true)
        let recovered = try XCTUnwrap(model.previews[0])
        let frames = try await ViewerImageFrames(file: recovered)
        _ = try await frames.frame(0)
        let count = await fixture.download.count(for: fixture.image.previewURL!)
        XCTAssertEqual(count, 2)
        XCTAssertFalse(model.failures.contains(0))
    }

    func testLateFailureFromSecondViewerCannotInvalidateRecoveredFile() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let first = ImageViewerModel(images: [fixture.image], cache: fixture.cache)
        let second = ImageViewerModel(images: [fixture.image], cache: fixture.cache)
        await first.loadOriginal(0)
        await second.loadOriginal(0)
        let old = try XCTUnwrap(first.originals[0])
        XCTAssertEqual(second.originals[0], old)
        await first.decodingFailed(0, file: old)
        await first.loadOriginal(0)
        let recovered = try XCTUnwrap(first.originals[0])
        XCTAssertNotEqual(recovered, old, "重新下载必须产生不同文件版本")
        await second.decodingFailed(0, file: old)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recovered.path))
        await second.loadOriginal(0)
        XCTAssertEqual(second.originals[0], recovered)
        let frames = try await ViewerImageFrames(file: recovered)
        _ = try await frames.frame(0)
        let count = await fixture.download.count(for: fixture.image.originalURL!)
        XCTAssertEqual(count, 2, "旧失败不能使已恢复文件再次下载")
    }

    private func assertCannotDecode(_ file: URL) async {
        do {
            let frames = try await ViewerImageFrames(file: file)
            _ = try await frames.frame(0)
            XCTFail("截断 PNG 不应解码成功")
        } catch { XCTAssertFalse(error.isCancellation) }
    }

    private func makeFixture(baseFails: Bool = false) throws -> (directory: URL, image: ViewerImage, cache: ImageFileCache, download: RecoveryDownload) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let image = ViewerImage(url: URL(string: "https://i0.hdslb.com/bfs/new_dyn/recovery.png")!)
        let valid = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }.pngData())
        let download = RecoveryDownload(valid: valid, failingURL: baseFails ? image.previewURL! : image.originalURL!)
        let cache = ImageFileCache(directory: directory, download: { try await download.fetch($0) })
        return (directory, image, cache, download)
    }
}

private actor RecoveryDownload {
    let valid: Data
    let failingURL: URL
    private var counts: [URL: Int] = [:]
    init(valid: Data, failingURL: URL) { self.valid = valid; self.failingURL = failingURL }
    func count(for url: URL) -> Int { counts[url, default: 0] }
    func fetch(_ request: URLRequest) throws -> (Data, URLResponse) {
        let url = request.url!
        counts[url, default: 0] += 1
        let data = url == failingURL && counts[url] == 1 ? Data(valid.prefix(33)) : valid
        return (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
