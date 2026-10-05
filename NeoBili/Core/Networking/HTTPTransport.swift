import Foundation

/// Sends already encoded requests. It knows nothing about App signatures or models.
/// The caller chooses retries: behavioral writes continue to use zero retries.
struct HTTPTransport {
    let session: URLSession

    func data(for request: URLRequest, retries: Int) async throws -> (Data, URLResponse) {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            let diagnosticID = await RecommendationDiagnostics.shared.begin(request, attempt: attempt)
            do {
                let result = try await session.data(for: request)
                await RecommendationDiagnostics.shared.finish(diagnosticID, data: result.0, response: result.1)
                return result
            } catch let error as URLError where attempt < retries && Self.isRetryable(error) {
                await RecommendationDiagnostics.shared.fail(diagnosticID, error: error)
                attempt += 1
                try await Task.sleep(for: .milliseconds(500 * attempt))
            } catch {
                await RecommendationDiagnostics.shared.fail(diagnosticID, error: error)
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
