import Foundation
import XCTest
@testable import NeoBili

final class ServiceGraphTransportTests: XCTestCase {
    func testInjectedSearchSignerFetchesItsKeyThroughTheSameIsolatedSession() async throws {
        let suite = "neobili.service-signing.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ServiceGraphProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let signer = WBISigner(session: session, defaults: defaults, cookieHeader: { "DedeUserID=41" })
        let snapshot = DeviceIdentity.AuthenticatedRequestSnapshot(sessionID: UUID(), accountID: 41,
            csrfToken: "fixture", cookieHeader: "DedeUserID=41", isLoggedIn: true)
        let client = APIClient(session: session, authentication: { snapshot },
            transport: HTTPTransport(session: session, diagnostics: RecommendationDiagnostics(enabled: { false }),
                                     observeResponse: { _, _ in }),
            signWebParameters: { try await signer.sign(params: $0) })
        let result = try await SearchService.live(client: client).searchVideos(keyword: "fixture", page: 1)
        XCTAssertEqual(result.numPages, 0)
        XCTAssertTrue(result.result?.isEmpty == true)
    }

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
        let body: String
        if request.url?.path.contains("/search/type") == true {
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard query.contains(where: { $0.name == "w_rid" && $0.value?.isEmpty == false }), account == 41 else {
                client?.urlProtocol(self, didFailWithError: URLError(.userAuthenticationRequired)); return
            }
            body = #"{"code":0,"data":{"result":[],"numPages":0}}"#
        } else {
            body = "{\"code\":0,\"data\":{\"isLogin\":true,\"mid\":\(account),\"wbi_img\":{\"img_url\":\"https://example.invalid/0123456789abcdef0123456789abcdef.png\",\"sub_url\":\"https://example.invalid/fedcba9876543210fedcba9876543210.png\"}}}"
        }
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
