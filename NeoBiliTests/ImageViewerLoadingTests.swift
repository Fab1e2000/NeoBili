import XCTest
@testable import NeoBili

@MainActor
final class ImageViewerLoadingTests: XCTestCase {
    private let first = URL(string: "https://example.com/first.jpg")!
    private let selected = URL(string: "https://example.com/selected.jpg")!

    func testSelectedImageAppearsBeforeSlowNeighbourCompletes() async throws {
        let probe = ImageDownloadProbe()
        let model = ImageViewerModel(images: [.init(url: first), .init(url: selected)]) {
            try await probe.fetch($0)
        }
        let prepare = Task { await model.prepare(startIndex: 1) }
        try await waitUntil { await probe.contains(self.selected) }
        let neighbourStarted = await probe.contains(first)
        XCTAssertFalse(neighbourStarted)
        await probe.succeed(selected)
        try await waitUntil { await probe.contains(self.first) }
        XCTAssertEqual(model.files[1], selected)
        XCTAssertNil(model.files[0], "慢图不能阻塞所选图片的展示")
        await probe.succeed(first)
        await prepare.value
        XCTAssertEqual(model.files[0], first)
    }

    func testFailedAndMissingImagesKeepTheirSlotsAndRetryIndependently() async throws {
        let probe = ImageDownloadProbe()
        let model = ImageViewerModel(images: [.init(url: nil), .init(url: selected)]) {
            try await probe.fetch($0)
        }
        await model.load(0)
        let attempt = Task { await model.load(1) }
        try await waitUntil { await probe.contains(self.selected) }
        await probe.fail(selected)
        await attempt.value
        XCTAssertEqual(model.failures, [0, 1])
        let retry = Task { await model.load(1, retry: true) }
        try await waitUntil { await probe.contains(self.selected) }
        await probe.succeed(selected)
        await retry.value
        XCTAssertEqual(model.files[1], selected)
        XCTAssertEqual(model.failures, [0])
    }

    func testNilURLDoesNotChangePayloadIdentityOrStartingPosition() {
        let payload = ImageViewerPayload(urls: [nil, selected], startIndex: 1)
        XCTAssertEqual(payload.id, payload.id)
        XCTAssertEqual(payload.startIndex, 1)
        XCTAssertEqual(payload.images.count, 2)
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("等待下载任务超时")
    }
}

private actor ImageDownloadProbe {
    private var pending: [URL: CheckedContinuation<URL, Error>] = [:]
    func fetch(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { pending[url] = $0 }
    }
    func contains(_ url: URL) -> Bool { pending[url] != nil }
    func succeed(_ url: URL) { pending.removeValue(forKey: url)?.resume(returning: url) }
    func fail(_ url: URL) { pending.removeValue(forKey: url)?.resume(throwing: URLError(.timedOut)) }
}
