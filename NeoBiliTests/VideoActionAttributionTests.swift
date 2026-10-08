import XCTest
import Synchronization
@testable import NeoBili

final class VideoActionAttributionTests: XCTestCase {
    func testActionsUseAppAuthenticationAndPreserveHistoryOrigin() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VideoActionProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let generation = UUID()
        let account = DeviceIdentity.AppRequestAccount(accessKey: "action-fixture", mid: 42, sessionID: generation)
        let client = APIClient(session: session, appAuthentication: { account })
        VideoActionProtocol.requests.withLock { $0 = [] }
        try await BiliAPI.likeVideo(aid: 123, like: false, entry: .history, expectedSessionID: generation, client: client)
        try await BiliAPI.addCoin(aid: 123, multiply: 2, entry: .history, expectedSessionID: generation, client: client)
        let result = try await BiliAPI.tripleAction(aid: 123, entry: .history, expectedSessionID: generation, client: client)
        XCTAssertTrue(result.didLike)
        XCTAssertFalse(result.didCoin)
        XCTAssertTrue(result.didFavorite)
        let requests = VideoActionProtocol.requests.withLock { $0 }
        XCTAssertEqual(requests.map { $0.url!.path }, ["/x/v2/view/like", "/x/v2/view/coin/add", "/x/v2/view/like/triple"])
        for request in requests {
            XCTAssertEqual(request.url?.host, "app.bilibili.com")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            let fields = fields(request)
            XCTAssertEqual(fields["from"], "64")
            XCTAssertEqual(fields["from_spmid"], "main.my-history.0.0")
            XCTAssertEqual(fields["spmid"], "united.player-video-detail.0.0")
            XCTAssertEqual(fields["access_key"], "action-fixture")
            XCTAssertNotNil(fields["sign"])
            XCTAssertNil(fields["csrf"])
        }
        XCTAssertEqual(fields(requests[0])["like"], "1", "App cancellation must send operation 1")
        XCTAssertEqual(fields(requests[1])["multiply"], "2")
        XCTAssertEqual(fields(requests[1])["select_like"], "0")
        XCTAssertEqual(fields(requests[1])["avtype"], "1")
    }

    func testTrackerWhitelistAndStaleOriginRejection() throws {
        let generation = UUID()
        var entry = PlaybackEntry.recommendation(trackID: "not-an-action-field", reportFlowData: "not-an-action-field")
        entry.loginSessionID = generation
        let parameters = try BiliAPI.videoActionParameters(aid: 123, entry: entry, sessionID: generation)
        XCTAssertEqual(Set(parameters.keys), Set(["aid", "from", "from_spmid", "spmid"]))
        XCTAssertEqual(parameters["from"], "7")
        XCTAssertThrowsError(try BiliAPI.videoActionParameters(aid: 123, entry: entry, sessionID: UUID()))
        let unknown = try BiliAPI.videoActionParameters(aid: 123, entry: .other, sessionID: generation)
        XCTAssertEqual(unknown["from"], "")
        XCTAssertEqual(unknown["from_spmid"], "")
    }

    func testFavoritesAttributionAndDislikeProviderWhitelist() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VideoActionProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let generation = UUID()
        let account = DeviceIdentity.AppRequestAccount(accessKey: "action-fixture", mid: 42, sessionID: generation)
        let client = APIClient(session: session, appAuthentication: { account })
        VideoActionProtocol.requests.withLock { $0 = [] }
        try await BiliAPI.likeVideo(aid: 456, like: true, entry: .favorites, expectedSessionID: generation, client: client)
        try await BiliAPI.dislikeVideo(aid: 456, dislike: true, entry: .favorites, expectedSessionID: generation, client: client)
        try await BiliAPI.dislikeVideo(aid: 456, dislike: false, entry: .favorites, expectedSessionID: generation, client: client)
        let requests = VideoActionProtocol.requests.withLock { $0 }
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(fields(requests[0])["like"], "0", "App liking must send operation 0, not web operation 1")
        XCTAssertEqual(fields(requests[0])["from"], "6")
        XCTAssertEqual(fields(requests[0])["from_spmid"], "main.my-fav.0.0")
        for request in requests.dropFirst() {
            XCTAssertEqual(request.url?.path, "/x/v2/view/dislike")
            XCTAssertEqual(fields(request)["from_spmid"], "main.my-fav.0.0")
            XCTAssertEqual(fields(request)["spmid"], "united.player-video-detail.0.0")
            XCTAssertNil(fields(request)["from"])
            XCTAssertNil(fields(request)["action_id"], "Do not invent an official pvUniqueID")
            XCTAssertNil(fields(request)["track_id"])
        }
        XCTAssertEqual(fields(requests[1])["dislike"], "0")
        XCTAssertEqual(fields(requests[2])["dislike"], "1")
    }

    func testOldAccountActionNeverReachesTransport() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VideoActionProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let account = DeviceIdentity.AppRequestAccount(accessKey: "new-fixture", mid: 42, sessionID: UUID())
        let client = APIClient(session: session, appAuthentication: { account })
        VideoActionProtocol.requests.withLock { $0 = [] }
        do {
            try await BiliAPI.likeVideo(aid: 123, like: true, entry: .history, expectedSessionID: UUID(), client: client)
            XCTFail("Old action must be rejected")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(VideoActionProtocol.requests.withLock { $0.isEmpty })
    }

    private func fields(_ request: URLRequest) -> [String: String] {
        let query = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        return Dictionary((URLComponents(string: "https://fixture/?" + query)?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
    }
}

private final class VideoActionProtocol: URLProtocol, @unchecked Sendable {
    static let requests = Mutex<[URLRequest]>([])
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            captured.httpBody = data
        }
        Self.requests.withLock { $0.append(captured) }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"code":0,"data":{"like":true,"coin":false,"fav":true}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
