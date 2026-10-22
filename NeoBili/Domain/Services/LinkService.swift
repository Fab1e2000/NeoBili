import Foundation

public struct LinkService: Sendable {
    public var resolve: @Sendable (URL) async throws -> URL? = { _ in throw ServiceError.unconfigured("Links.resolve") }

    public init(
        resolve: @escaping @Sendable (URL) async throws -> URL? = { _ in throw ServiceError.unconfigured("Links.resolve") }
    ) {
        self.resolve = resolve
    }
}
