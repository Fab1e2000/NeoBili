import SwiftUI
import XCTest
import Synchronization
@testable import NeoBili

@MainActor
final class WatchLaterUpgradeTests: XCTestCase {
    private func item(_ id: Int) throws -> WatchLaterItem {
        try JSONDecoder().decode(WatchLaterItem.self, from: Data("""
        {"aid":\(id),"bvid":"BVfixture\(id)","cid":\(id),"title":"稍后再看测试视频 \(id)","duration":120,"owner":{"mid":1,"name":"测试作者"}}
        """.utf8))
    }

    func testV2RequestUsesVerifiedSignedAPIHostAndResponseCursor() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [WatchLaterProtocol.self]
        let urlSession = URLSession(configuration: config); defer { urlSession.invalidateAndCancel() }
        let generation = UUID()
        let account = DeviceIdentity.AppRequestAccount(accessKey: "fixture-key", mid: 1, sessionID: generation)
        let client = APIClient(session: urlSession, appAuthentication: { account })
        WatchLaterProtocol.request.withLock { $0 = nil }
        let page = try await BiliAPI.watchLaterPage(startKey: "next", splitKey: "split", expectedSessionID: generation, client: client)
        let request = try XCTUnwrap(WatchLaterProtocol.request.withLock { $0 })
        XCTAssertEqual(request.url?.host, "api.bilibili.com")
        XCTAssertEqual(request.url?.path, "/x/v2/history/toview/v2/list")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        let query = Dictionary(uniqueKeysWithValues: URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["start_key"], "next"); XCTAssertEqual(query["split_key"], "split")
        XCTAssertEqual(query["asc"], "false"); XCTAssertEqual(query["sort_field"], "1")
        XCTAssertNotNil(query["sign"]); XCTAssertNil(query["pn"]); XCTAssertNil(query["ps"])
        XCTAssertEqual(page.items.first?.upper?.name, "fixture")
        XCTAssertEqual(page.nextKey, "next2"); XCTAssertTrue(page.hasMore)
    }

    func testPaginationDeduplicatesAndStopsRepeatedCursor() async throws {
        let session = UUID(); let first = try item(1), second = try item(2)
        var calls: [(String, String)] = []
        let model = WatchLaterModel(client: .init(load: { key, split, _ in
            calls.append((key, split))
            return key.isEmpty ? .init(items: [first], nextKey: "next", splitKey: "split", hasMore: true)
                : .init(items: [first, second], nextKey: "next", splitKey: "split", hasMore: true)
        }, remove: { _, _ in XCTFail("No mutation expected") }, session: { session }))
        await model.load(); await model.load(); await model.load()
        XCTAssertEqual(model.items.map(\.id), [1, 2]); XCTAssertFalse(model.hasMore)
        XCTAssertEqual(calls.count, 2); XCTAssertEqual(calls[1].0, "next"); XCTAssertEqual(calls[1].1, "split")
    }

    func testPartialBatchFailureRestoresOnlyFailedItemsAndUndoWritesNothing() async throws {
        let session = UUID(); let items = try [item(1), item(2), item(3)]
        var removed: [Int] = []
        let model = WatchLaterModel(client: .init(load: { _, _, _ in .init(items: items) }, remove: { id, _ in
            removed.append(id)
            if id == 2 { throw URLError(.notConnectedToInternet) }
        }, session: { session }))
        await model.load()
        let failure = await model.remove(ids: [1, 2], confirm: { true })
        XCTAssertNotNil(failure); XCTAssertEqual(removed, [1, 2]); XCTAssertEqual(model.items.map(\.id), [2, 3])
        _ = await model.remove(ids: [2, 3], confirm: { false })
        XCTAssertEqual(removed, [1, 2]); XCTAssertEqual(model.items.map(\.id), [2, 3])
    }

    func testFailedPageRetainsItemsAndRetriesSameCursor() async throws {
        let session = UUID(); let first = try item(1), second = try item(2); var fail = true
        let model = WatchLaterModel(client: .init(load: { key, _, _ in
            if key.isEmpty { return .init(items: [first], nextKey: "next", hasMore: true) }
            if fail { fail = false; throw URLError(.timedOut) }
            return .init(items: [second])
        }, remove: { _, _ in }, session: { session }))
        await model.load(); await model.load()
        XCTAssertEqual(model.items.map(\.id), [1]); XCTAssertNotNil(model.errorMessage)
        await model.load(); XCTAssertEqual(model.items.map(\.id), [1, 2]); XCTAssertNil(model.errorMessage)
    }

    func testAccountChangeCannotRestoreOldAccountRemoval() async throws {
        var session = UUID(); let old = try item(1), new = try item(2)
        let oldSession = session
        let model = WatchLaterModel(client: .init(load: { _, _, owner in
            .init(items: [owner == oldSession ? old : new])
        }, remove: { _, _ in XCTFail("Stale removal must not send") }, session: { session }))
        await model.load()
        _ = await model.remove(ids: [1], confirm: { session = UUID(); return true })
        await model.load()
        XCTAssertEqual(model.items.map(\.id), [2]); XCTAssertFalse(model.isRemoving)
    }

    func testSelectionScreenshotsLightDarkAndLargeText() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow; let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        let fixture = try [item(1), item(2), item(3)]
        let session = UUID()
        let model = WatchLaterModel(client: .init(load: { _, _, _ in .init(items: fixture, nextKey: "next", hasMore: true) },
            remove: { _, _ in XCTFail("Rendering must not write") }, session: { session }))
        let account = AccountStore(monitorNetwork: false)
        for (name, style, size) in [("light", UIUserInterfaceStyle.light, DynamicTypeSize.large),
                                    ("dark", .dark, .large), ("large-text", .light, .accessibility2),
                                    ("landscape", .light, .large)] {
            var frames: [String: CGRect] = [:]
            let host = UIHostingController(rootView: NavigationStack { WatchLaterView(model: model, onLayout: { frames = $0 }) }
                .environment(account).environment(NowPlayingStore()).environment(ActionFeedback()).dynamicTypeSize(size))
            window.rootViewController = host
            window.frame = CGRect(x: 0, y: 0, width: name == "landscape" ? 874 : 402, height: name == "landscape" ? 402 : 874)
            window.overrideUserInterfaceStyle = style; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(150))
            model.isSelecting = true; model.selectedIDs = [1]
            try await Task.sleep(for: .milliseconds(150)); window.layoutIfNeeded()
            XCTAssertEqual(model.items.count, 3); XCTAssertEqual(model.selectedIDs, [1])
            let first = try XCTUnwrap(frames["card-1"])
            if let second = frames["card-2"] { XCTAssertLessThanOrEqual(first.maxY, second.minY) }
            if size.isAccessibilitySize {
                let title = try XCTUnwrap(frames["title-1"])
                let author = try XCTUnwrap(frames["author-1"])
                let duration = try XCTUnwrap(frames["duration-1"])
                for rect in [title, author, duration] {
                    XCTAssertGreaterThanOrEqual(rect.minY, first.minY)
                    XCTAssertLessThanOrEqual(rect.maxY, first.maxY)
                    XCTAssertGreaterThanOrEqual(rect.minX, first.minX)
                    XCTAssertLessThanOrEqual(rect.maxX, first.maxX)
                }
                XCTAssertLessThanOrEqual(title.maxY, author.minY)
                XCTAssertLessThanOrEqual(author.maxY, duration.minY)
            }
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = "watchlater-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
            try image.pngData()?.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("watchlater-\(name).png"))
        }
    }
}

private final class WatchLaterProtocol: URLProtocol, @unchecked Sendable {
    static let request = Mutex<URLRequest?>(nil)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.request.withLock { $0 = request }
        let data = Data("""
        {"code":0,"data":{"has_more":true,"next_key":"next2","split_key":"split","tab_type":1,"list":[{"aid":1,"bvid":"BVfixture1","title":"fixture","owner":{"mid":1,"name":"fixture"}}]}}
        """.utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
