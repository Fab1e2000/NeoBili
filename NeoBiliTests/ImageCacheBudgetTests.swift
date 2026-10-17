import XCTest
import UIKit
@testable import NeoBili

@MainActor
final class ImageCacheBudgetTests: XCTestCase {
    func testBudgetEvictsLeastRecentlyUsedFilesButKeepsViewerAndShareFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }.pngData())
        let clock = ImageCacheClock()
        let cache = ImageFileCache(directory: directory, byteLimit: data.count * 2, now: { clock.date }) { request in
            (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let owner = UUID()
        let a = URL(string: "https://example.com/a.png")!
        let b = URL(string: "https://example.com/b.png")!
        let c = URL(string: "https://example.com/c.png")!
        let fileA = try await cache.localFile(for: a, owner: owner)
        clock.advance()
        let fileB = try await cache.localFile(for: b)
        clock.advance()
        let fileC = try await cache.localFile(for: c)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileA.path), "查看/分享持有的文件不可淘汰")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileB.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileC.path))
        await cache.release(owner: owner)
    }

    func testActiveFilesMayExceedBudgetUntilViewerReleasesThem() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }.pngData())
        let cache = ImageFileCache(directory: directory, byteLimit: 0, download: { request in
            (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let owner = UUID()
        let file = try await cache.localFile(for: URL(string: "https://example.com/active.png")!, owner: owner)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        await cache.release(owner: owner)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testReleasedViewerDoesNotRetainLateDownloadBeyondBudget() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }.pngData())
        let started = expectation(description: "download started")
        let gate = BudgetDownloadGate()
        let cache = ImageFileCache(directory: directory, byteLimit: 0) { request in
            await gate.wait(started: started)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let owner = UUID()
        let loading = Task { try await cache.localFile(for: URL(string: "https://example.invalid/late.png")!, owner: owner) }
        await fulfillment(of: [started], timeout: 2)
        await cache.release(owner: owner)
        await gate.release()
        let file = try await loading.value
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testExpiredFilesAreRemovedOnNextCacheActivity() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }.pngData())
        let clock = ImageCacheClock()
        let cache = ImageFileCache(directory: directory, maxAge: 1, now: { clock.date }) { request in
            (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let old = try await cache.localFile(for: URL(string: "https://example.com/old.png")!)
        clock.advance(by: 2)
        _ = try await cache.localFile(for: URL(string: "https://example.com/new.png")!)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
    }
}

private final class ImageCacheClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_000_000)
    var date: Date { lock.withLock { value } }
    func advance(by seconds: TimeInterval = 1) { lock.withLock { value.addTimeInterval(seconds) } }
}

private actor BudgetDownloadGate {
    private var continuation: CheckedContinuation<Void, Never>?
    func wait(started: XCTestExpectation) async {
        await withCheckedContinuation { continuation = $0; started.fulfill() }
    }
    func release() { continuation?.resume(); continuation = nil }
}
