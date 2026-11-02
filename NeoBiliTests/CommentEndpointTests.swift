#if canImport(NeoBiliDomain)
@testable import NeoBiliDomain
#endif
#if canImport(NeoBiliData)
@testable import NeoBiliData
#endif
import XCTest
import Synchronization
@testable import NeoBili

@MainActor
final class CommentEndpointTests: XCTestCase {
    func testSortingUsesServerParametersForVideosAndDynamics() async throws {
        let context = try await makeContext()
        defer { context.close() }
        let service = CommentService.live(client: context.client, identity: context.identity)
        _ = try await service.comments(oid: 99, type: 1, page: 2)
        _ = try await service.comments(oid: 88, type: 17, page: 1, sort: .latest)
        let requests = CommentEndpointProtocol.requests.withLock { $0 }
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map { $0.httpMethod }, ["GET", "GET"])
        XCTAssertEqual(requests.map { $0.url?.path }, ["/x/v2/reply", "/x/v2/reply"])
        XCTAssertEqual(parameters(requests[0]), ["oid": "99", "type": "1", "pn": "2", "ps": "20", "sort": "1"])
        XCTAssertEqual(parameters(requests[1]), ["oid": "88", "type": "17", "pn": "1", "ps": "20", "sort": "0"])
    }

    func testDeleteUsesBoundSessionCSRFAndSinglePost() async throws {
        let context = try await makeContext()
        defer { context.close() }
        let service = CommentService.live(client: context.client, identity: context.identity)
        try await service.deleteComment(oid: 88, type: 17, rpid: 99, expectedSessionID: context.identity.loginSessionID)
        let requests = CommentEndpointProtocol.requests.withLock { $0 }
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/x/v2/reply/del")
        XCTAssertEqual(parameters(request), ["oid": "88", "type": "17", "rpid": "99", "csrf": "fixture-csrf"])
        XCTAssertTrue(request.value(forHTTPHeaderField: "Cookie")?.contains("SESSDATA=fixture-session") == true)
        XCTAssertFalse(request.httpShouldHandleCookies)
    }

    func testSessionChangeBetweenCSRFAndCookieReadSendsNoDelete() async throws {
        for account in ["42", "7"] {
            let context = try await makeContext()
            defer { context.close() }
            let confirmed = context.identity.loginSessionID
            let identity = context.identity
            let client = APIClient(session: context.session, authentication: {
                await identity.saveLogin(.init(sessdata: "new-session", biliJct: "new-csrf", dedeUserID: account), accessKey: nil)
                return await identity.authenticatedRequestSnapshot()
            })
            do {
                try await CommentService.live(client: client, identity: identity)
                    .deleteComment(oid: 1, type: 1, rpid: 2, expectedSessionID: confirmed)
                XCTFail("An old confirmation must not use a later login")
            } catch { XCTAssertTrue(error.isCancellation) }
            XCTAssertTrue(CommentEndpointProtocol.requests.withLock { $0.isEmpty })
        }
    }

    func testServerDeleteFailureIsPropagatedWithoutRetry() async throws {
        let context = try await makeContext()
        defer { context.close() }
        CommentEndpointProtocol.failure.withLock { $0 = true }
        do {
            try await CommentService.live(client: context.client, identity: context.identity)
                .deleteComment(oid: 1, type: 1, rpid: 2, expectedSessionID: context.identity.loginSessionID)
            XCTFail("Server rejection must keep the comment visible")
        } catch { XCTAssertFalse(error.isCancellation) }
        XCTAssertEqual(CommentEndpointProtocol.requests.withLock { $0.count }, 1)
    }

    private func parameters(_ request: URLRequest) -> [String: String] {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.compactMap { item in item.value.map { (item.name, $0) } })
    }
    private struct Context {
        let identity: DeviceIdentity
        let session: URLSession
        let client: APIClient
        let defaults: UserDefaults
        let suite: String
        func close() { session.invalidateAndCancel(); defaults.removePersistentDomain(forName: suite) }
    }
    private func makeContext() async throws -> Context {
        let suite = "neobili.comment-endpoint.tests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let identity = DeviceIdentity(defaults: defaults, credentials: .memory(), allowsNetwork: false, purgeCookies: {})
        await identity.saveLogin(.init(sessdata: "fixture-session", biliJct: "fixture-csrf", dedeUserID: "42"), accessKey: nil)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CommentEndpointProtocol.self]
        let session = URLSession(configuration: configuration)
        CommentEndpointProtocol.requests.withLock { $0 = [] }
        CommentEndpointProtocol.failure.withLock { $0 = false }
        let client = APIClient(session: session, authentication: { await identity.authenticatedRequestSnapshot() })
        return Context(identity: identity, session: session, client: client, defaults: defaults, suite: suite)
    }
}

private final class CommentEndpointProtocol: URLProtocol, @unchecked Sendable {
    static let requests = Mutex<[URLRequest]>([])
    static let failure = Mutex(false)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.withLock { $0.append(request) }
        let body: String
        if Self.failure.withLock({ $0 }) { body = #"{"code":12002,"message":"fixture rejection"}"# }
        else if request.url?.path == "/x/v2/reply" {
            body = #"{"code":0,"data":{"page":{"num":1,"size":20,"count":0},"replies":[]}}"#
        } else { body = #"{"code":0,"data":{}}"# }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
