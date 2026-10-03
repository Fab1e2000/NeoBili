import XCTest
import Synchronization
@testable import NeoBili

@MainActor
final class AppRelatedTests: XCTestCase {
    func testOfficialGzipEnvelopeAndCorruptTrailer() throws {
        let hex = "1f8b08000000000002ff13624fcbac28292d4a0500d0e873f609000000"
        let bytes = stride(from: 0, to: hex.count, by: 2).map { index -> UInt8 in
            let start = hex.index(hex.startIndex, offsetBy: index)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
        }
        let gzip = Data(bytes)
        var frame = AppProto.frame(gzip); frame[0] = 1
        XCTAssertEqual(try AppProto.unframe(frame), Data([18, 7]) + Data("fixture".utf8))
        frame[frame.count - 8] ^= 1
        XCTAssertThrowsError(try AppProto.unframe(frame))
    }

    func testAppTransportUsesOwnCredentialMetadataAndRejectsOldLogin() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelatedProtocol.self]
        let transport = URLSession(configuration: config)
        defer { transport.invalidateAndCancel() }
        let login = UUID()
        let account = DeviceIdentity.AppRequestAccount(accessKey: "own-fixture", mid: 42, sessionID: login)
        let client = APIClient(session: transport, appAuthentication: { account })
        RelatedProtocol.requests.withLock { $0 = [] }
        let result = try await client.appGRPC(path: "bilibili.app.viewunite.v1.View/View", payload: Data(),
            expectedSessionID: login, headers: ["buvid": "own-device"])
        XCTAssertTrue(result.isEmpty)
        let request = try XCTUnwrap(RelatedProtocol.requests.withLock { $0.first })
        XCTAssertEqual(request.url?.host, "grpc.biliapi.net")
        XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "identify_v1 own-fixture")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/grpc")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        let metadata = try AppProto(XCTUnwrap(Data(base64Encoded: XCTUnwrap(request.value(forHTTPHeaderField: "x-bili-metadata-bin")))))
        XCTAssertEqual(metadata.text(1), "own-fixture")
        XCTAssertEqual(metadata.text(2), "iphone")
        XCTAssertEqual(metadata.text(6), "own-device")
        do {
            _ = try await client.appGRPC(path: "bilibili.app.viewunite.v1.View/View", payload: Data(),
                expectedSessionID: UUID(), headers: [:])
            XCTFail("Old login must be rejected before sending")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(RelatedProtocol.requests.withLock { $0.count }, 1)
    }

    func testVideoPageUsesCredentialSessionRatherThanLikeStateSession() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "related-session-\(UUID().uuidString)"))
        let identity = DeviceIdentity(defaults: defaults, credentials: .memory(), allowsNetwork: false)
        let likeStore = VideoLikeStore()
        let login = identity.loginSessionID
        XCTAssertNotEqual(likeStore.sessionID, login)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelatedProtocol.self]
        let transport = URLSession(configuration: config)
        defer { transport.invalidateAndCancel() }
        let client = APIClient(session: transport, appAuthentication: {
            .init(accessKey: "own-fixture", mid: 42, sessionID: identity.loginSessionID)
        })
        RelatedProtocol.requests.withLock { $0 = [] }
        let model = VideoDetailViewModel(bvid: "BV17x411w7KC", likeStore: likeStore,
                                        identity: identity, relatedClient: client)
        await model.loadRelated()
        XCTAssertEqual(RelatedProtocol.requests.withLock { $0.count }, 1,
                       "Distinct local like-state and credential sessions must not cancel related requests")
        await model.loadRelated()
        XCTAssertEqual(RelatedProtocol.requests.withLock { $0.count }, 1)
    }
    func testPaginationStopsOnRepeatedServerCursorAndInitialIsNotRefetched() async throws {
        let cursor = AppProto.string(2, "same-cursor")
        let payload = AppProto.bytes(2, cursor)
        let page = try AppRelatedPage(payload: payload, isView: false, accountSession: UUID())
        var cursors: [Data?] = []
        let model = VideoDetailViewModel(bvid: "BVFixture", relatedPageLoader: { cursor in
            cursors.append(cursor)
            return page
        })
        await model.loadRelated()
        await model.loadRelated()
        XCTAssertTrue(model.canLoadMoreRelated)
        await model.loadMoreRelated()
        await model.loadMoreRelated()
        XCTAssertEqual(cursors.count, 2)
        XCTAssertNil(cursors[0])
        XCTAssertEqual(cursors[1], cursor)
        XCTAssertFalse(model.canLoadMoreRelated)
    }

    func testMalformedFramesAndProtobufAreRejected() throws {
        XCTAssertThrowsError(try AppProto(Data([0])))
        XCTAssertThrowsError(try AppProto(Data([10, 255, 255])))
        XCTAssertThrowsError(try AppProto.unframe(Data([0, 0, 0, 0, 2, 1])))
        XCTAssertThrowsError(try AppProto.unframe(Data([2, 0, 0, 0, 0])))
        let payload = AppProto.string(2, "fixture") + AppProto.integer(3, 64)
        XCTAssertEqual(try AppProto.unframe(AppProto.frame(payload)), payload)
    }

    func testViewAndPaginationCarryActualEntryAndSharedPlaybackSession() throws {
        let login = UUID()
        let entry = PlaybackEntry(source: .related, trackID: "fixture-track", reportFlowData: "fixture-flow", loginSessionID: login)
        let payload = AppRelatedPage.viewRequest(bvid: "BV17x411w7KC", aid: 170001, entry: entry,
                                                playbackSession: "fixture-playback", accountSession: login)
        let view = try AppProto(payload)
        XCTAssertEqual(view.text(3), "2")
        XCTAssertEqual(view.text(5), "united.player-video-detail.relatedvideo.0")
        XCTAssertEqual(view.text(6), "fixture-playback")
        XCTAssertEqual(view.text(8), "fixture-track")
        let next = AppProto.integer(1, 20) + AppProto.string(2, "opaque-own-cursor")
        let more = try AppProto(AppRelatedPage.moreRequest(bvid: "BV17x411w7KC", aid: 170001,
            entry: entry, playbackSession: "fixture-playback", accountSession: login, pagination: next))
        XCTAssertEqual(more.data(7), next)
        XCTAssertEqual(more.text(8), view.text(6))
        XCTAssertEqual(more.text(10), view.text(8))
        let stale = try AppProto(AppRelatedPage.viewRequest(bvid: "BV17x411w7KC", aid: 170001,
            entry: entry, playbackSession: "fixture-playback", accountSession: UUID()))
        XCTAssertNil(stale.text(8), "Never reuse tracking from a different account session")
    }

    func testAppCardTrackingIsRetainedAndAdsAreNotConvertedToVideos() throws {
        let login = UUID()
        let basic = AppProto.string(1, "Fixture related") + AppProto.string(3, "https://example.invalid/cover")
            + AppProto.string(5, "fixture-track") + AppProto.integer(12, 170001) + AppProto.string(15, "fixture-flow")
        let av = AppProto.integer(1, 30) + AppProto.integer(2, 123)
        let card = AppProto.integer(1, 1) + AppProto.bytes(2, av) + AppProto.bytes(12, basic)
        let ad = AppProto.integer(1, 5) + AppProto.bytes(12, basic)
        let cursor = AppProto.string(2, "next-page")
        let page = try AppRelatedPage(payload: AppProto.bytes(1, card) + AppProto.bytes(1, ad) + AppProto.bytes(2, cursor),
                                      isView: false, accountSession: login)
        XCTAssertEqual(page.videos.count, 1)
        XCTAssertEqual(page.videos[0].playbackEntry.parameters(for: login)["track_id"], "fixture-track")
        XCTAssertEqual(page.videos[0].playbackEntry.parameters(for: login)["report_flow_data"], "fixture-flow")
        XCTAssertEqual(page.pagination, cursor)
        XCTAssertTrue(page.canLoadMore)
        let config = AppProto.bytes(3, cursor) + AppProto.integer(4, 1)
        let relates = AppProto.bytes(1, card) + AppProto.bytes(2, config)
        let module = AppProto.bytes(22, relates)
        let introduction = AppProto.bytes(2, module)
        let tabModule = AppProto.bytes(2, introduction)
        let tab = AppProto.bytes(1, tabModule)
        let view = try AppRelatedPage(payload: AppProto.bytes(5, tab), isView: true, accountSession: login)
        XCTAssertEqual(view.videos.map(\.bvid), page.videos.map(\.bvid))
        XCTAssertEqual(view.pagination, cursor)
        XCTAssertTrue(view.canLoadMore)
    }
}

private final class RelatedProtocol: URLProtocol, @unchecked Sendable {
    static let requests = Mutex<[URLRequest]>([])
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.withLock { $0.append(request) }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: ["Content-Type": "application/grpc", "grpc-status": "0"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: AppProto.frame(Data()))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
