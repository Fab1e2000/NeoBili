import Foundation

/// Immutable-by-convention dependency graph. Tests create local copies and replace
/// only the operations they exercise; no process-wide override is necessary.
struct ApplicationServices: Sendable {
    var exportDiagnostics: @Sendable () async throws -> URL = { throw ServiceError.unconfigured("exportDiagnostics") }
    var telemetry = TelemetryService()
    var authentication = AuthenticationService()
    var session: SessionService
    var links = LinkService()
    var search = SearchService()
    var library = LibraryService()
    var video = VideoService()
    var account = AccountService()
    var comment = CommentService()
    var streaming = LiveService()
    var community = CommunityService()
    var recommendation = RecommendationService()
}

enum ServiceError: LocalizedError {
    case unconfigured(String)
    var errorDescription: String? {
        switch self { case .unconfigured(let operation): "Service not configured: \(operation)" }
    }
}
