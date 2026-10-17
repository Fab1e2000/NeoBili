import Foundation
import XCTest
@testable import NeoBili

final class ServiceGraphTransportTests: XCTestCase {
    func testIndependentAccountAdaptersUseTheirInjectedTransportAndCredentials() async throws {
        for account in [41, 42] {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [ServiceGraphProtocol.self]
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let snapshot = DeviceIdentity.AuthenticatedRequestSnapshot(sessionID: UUID(), accountID: account,
                csrfToken: "fixture", cookieHeader: "DedeUserID=\(account)", isLoggedIn: true)
            let service = AccountService.live(client: APIClient(session: session, authentication: { snapshot }))
            let profile = try await service.myProfile()
            XCTAssertEqual(profile.mid, account)
        }
    }
}

private final class ServiceGraphProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let cookie = request.value(forHTTPHeaderField: "Cookie") ?? ""
        let account = cookie == "DedeUserID=41" ? 41 : cookie == "DedeUserID=42" ? 42 : 0
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"code\":0,\"data\":{\"isLogin\":true,\"mid\":\(account)}}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
