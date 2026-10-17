#if canImport(NeoBiliDomain)
@testable import NeoBiliDomain
#endif
import Foundation
@testable import NeoBili

/// Local identity and explicitly configured transport for deterministic tests.
/// Unconfigured signing fails instead of reaching the production signer.
enum TestNetworking {
    static func identity() -> DeviceIdentity {
        DeviceIdentity(defaults: UserDefaults(suiteName: "neobili.test-networking.\(UUID().uuidString)")!,
                       credentials: .memory(), allowsNetwork: false,
                       networkSnapshot: { .init(connection: .unknown) }, purgeCookies: {})
    }

    static func client(identity: DeviceIdentity, session: URLSession? = nil,
                       authentication: (@Sendable () async -> DeviceIdentity.AuthenticatedRequestSnapshot)? = nil,
                       signWebParameters: @escaping @Sendable ([String: String]) async throws -> [String: String] = {
                           _ in throw ServiceError.unconfigured("test WBI signer")
                       }) -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestNetworkingBlocker.self]
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return APIClient(transport: HTTPTransport(session: session ?? URLSession(configuration: configuration),
            diagnostics: RecommendationDiagnostics(enabled: { false }), observeResponse: { _, _ in }),
            authentication: authentication ?? { await identity.authenticatedRequestSnapshot() },
            appAuthentication: { await identity.appAccount() },
            appHeaders: { try await identity.appRequestHeaders(expectedSessionID: $0) },
            signWebParameters: signWebParameters)
    }

    @MainActor static func stream() -> LiveDanmakuConnection {
        let identity = identity()
        return LiveDanmakuConnection(identity: identity, client: client(identity: identity))
    }
}

private final class TestNetworkingBlocker: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
