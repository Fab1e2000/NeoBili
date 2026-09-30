import Foundation

/// Regression is a separate build, so environment overrides cannot enable live traffic.
enum AppNetwork {
    static var isRegression: Bool {
        #if NEOBILI_REGRESSION
        true
        #else
        false
        #endif
    }

    static let session: URLSession = {
        guard isRegression else { return .shared }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RegressionNetworkBlocker.self]
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()
}

private final class RegressionNetworkBlocker: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}
