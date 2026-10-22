import Foundation

/// Sends already encoded requests. It knows nothing about App signatures or models.
/// The caller chooses retries: behavioral writes continue to use zero retries.
public struct HTTPTransport: Sendable {
    let session: URLSession
    let diagnostics: RecommendationDiagnostics
    let observeResponse: @Sendable (HTTPURLResponse, URLRequest) async -> Void

    public init(session: URLSession, diagnostics: RecommendationDiagnostics,
         observeResponse: @escaping @Sendable (HTTPURLResponse, URLRequest) async -> Void) {
        self.session = session
        self.diagnostics = diagnostics
        self.observeResponse = observeResponse
    }

    func data(for request: URLRequest, retries: Int) async throws -> (Data, URLResponse) {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            let diagnosticID = await diagnostics.begin(request, attempt: attempt)
            do {
                let result = try await session.data(for: request)
                if !AppNetwork.isRegression, let http = result.1 as? HTTPURLResponse {
                    await observeResponse(http, request)
                }
                await diagnostics.finish(diagnosticID, data: result.0, response: result.1)
                return result
            } catch let error as URLError where attempt < retries && Self.isRetryable(error) {
                await diagnostics.fail(diagnosticID, error: error)
                attempt += 1
                try await Task.sleep(for: .milliseconds(500 * attempt))
            } catch {
                await diagnostics.fail(diagnosticID, error: error)
                throw error
            }
        }
    }

    static func isRetryable(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet: true
        default: false
        }
    }
}
