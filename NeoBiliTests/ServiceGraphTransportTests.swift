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

    func testIndependentWriteAdaptersKeepCookieCSRFAndSessionInTheSameGraph() async throws {
        for account in [41, 42] {
            let suite = "neobili.service-write.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let identity = DeviceIdentity(defaults: defaults, credentials: .memory(), allowsNetwork: false, purgeCookies: {})
            await identity.setLoginCookies(sessdata: "fixture", biliJct: "csrf-\(account)", dedeUserID: String(account))
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [ServiceGraphProtocol.self]
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            let client = APIClient(session: session, authentication: { await identity.authenticatedRequestSnapshot() })
            let service = LibraryService.live(client: client, identity: identity)
            try await service.deleteHistory(kid: "archive_1", expectedSessionID: identity.loginSessionID)
        }
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
        let account = cookie.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("DedeUserID=") }.flatMap { Int($0.dropFirst("DedeUserID=".count)) } ?? 0
        if request.httpMethod == "POST" {
            var body = request.httpBody ?? Data()
            if body.isEmpty, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    guard count > 0 else { break }
                    body.append(contentsOf: bytes.prefix(count))
                }
            }
            guard [41, 42].contains(account), String(decoding: body, as: UTF8.self).contains("csrf=csrf-\(account)") else {
                client?.urlProtocol(self, didFailWithError: URLError(.userAuthenticationRequired)); return
            }
        }
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
