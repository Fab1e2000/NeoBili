import Foundation

/// Immutable-by-convention dependency graph. Tests create local copies and replace
/// only the operations they exercise; no process-wide override is necessary.
public struct ApplicationServices: Sendable {
    public var currentAppBuvid: @Sendable () async -> String = { "" }
    public var exportDiagnostics: @Sendable () async throws -> URL = { throw ServiceError.unconfigured("exportDiagnostics") }
    public var telemetry = TelemetryService()
    public var authentication = AuthenticationService()
    public var session: SessionService
    public var links = LinkService()
    public var search = SearchService()
    public var library = LibraryService()
    public var video = VideoService()
    public var account = AccountService()
    public var comment = CommentService()
    public var streaming = LiveService()
    public var community = CommunityService()
    public var recommendation = RecommendationService()

    public init(
        currentAppBuvid: @escaping @Sendable () async -> String = { "" },
        exportDiagnostics: @escaping @Sendable () async throws -> URL = { throw ServiceError.unconfigured("exportDiagnostics") },
        telemetry: TelemetryService = TelemetryService(),
        authentication: AuthenticationService = AuthenticationService(),
        session: SessionService,
        links: LinkService = LinkService(),
        search: SearchService = SearchService(),
        library: LibraryService = LibraryService(),
        video: VideoService = VideoService(),
        account: AccountService = AccountService(),
        comment: CommentService = CommentService(),
        streaming: LiveService = LiveService(),
        community: CommunityService = CommunityService(),
        recommendation: RecommendationService = RecommendationService()
    ) {
        self.currentAppBuvid = currentAppBuvid
        self.exportDiagnostics = exportDiagnostics
        self.telemetry = telemetry
        self.authentication = authentication
        self.session = session
        self.links = links
        self.search = search
        self.library = library
        self.video = video
        self.account = account
        self.comment = comment
        self.streaming = streaming
        self.community = community
        self.recommendation = recommendation
    }
}

public enum ServiceError: LocalizedError {
    case unconfigured(String)
    public var errorDescription: String? {
        switch self { case .unconfigured(let operation): "Service not configured: \(operation)" }
    }
}
