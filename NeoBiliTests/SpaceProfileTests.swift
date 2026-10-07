import XCTest
import Synchronization
@testable import NeoBili

@MainActor
final class SpaceProfileTests: XCTestCase {
    func testProfileRequestsAppBackgroundAndKeepsWebCardOnAppFailure() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SpaceProfileProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let generation = UUID()
        let client = APIClient(session: session, appAuthentication: { .init(accessKey: nil, mid: nil, sessionID: generation) })
        for fail in [false, true] {
            SpaceProfileProtocol.state.withLock { $0 = (fail, []) }
            let card = try await BiliAPI.spaceProfile(mid: 42, client: client)
            XCTAssertEqual(card.name, "fixture")
            XCTAssertEqual(card.bannerURL(isDark: false)?.lastPathComponent, fail ? "web.jpg" : "app.jpg")
            let requests = SpaceProfileProtocol.state.withLock { $0.requests }
            XCTAssertEqual(requests.count, 2, "Optional background failure must not retry")
            let app = try XCTUnwrap(requests.first { $0.url?.path == "/x/v2/space" })
            XCTAssertEqual(app.url?.host, "app.bilibili.com")
            let query = URLComponents(url: app.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            XCTAssertEqual(query.first { $0.name == "vmid" }?.value, "42")
            XCTAssertNotNil(query.first { $0.name == "sign" }?.value)
        }
    }
}

private final class SpaceProfileProtocol: URLProtocol, @unchecked Sendable {
    static let state = Mutex<(fail: Bool, requests: [URLRequest])>((false, []))
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let fail = Self.state.withLock { $0.requests.append(request); return $0.fail }
        let isApp = request.url?.path == "/x/v2/space"
        let body = isApp
            ? (fail ? #"{"code":-400,"message":"fixture error"}"# : #"{"code":0,"data":{"images":{"imgUrl":"https://i0.hdslb.com/app.jpg"}}}"#)
            : #"{"code":0,"data":{"card":{"name":"fixture"},"space":{"l_img":"https://i0.hdslb.com/web.jpg"}}}"#
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
