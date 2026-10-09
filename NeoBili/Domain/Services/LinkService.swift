import Foundation

struct LinkService: Sendable {
    var resolve: @Sendable (URL) async throws -> URL? = { _ in throw ServiceError.unconfigured("Links.resolve") }
}
