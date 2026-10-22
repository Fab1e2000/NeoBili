import Foundation

/// Account operations available to application state and views.
/// Values can be replaced per model or view hierarchy without changing global state.
public struct AccountService: Sendable {
    public var myProfileOperation: @Sendable () async throws -> AccountProfilePayload = { throw ServiceError.unconfigured("Account.myProfile") }

    public func myProfile() async throws -> AccountProfilePayload {
        try await myProfileOperation()
    }

    public init(
        myProfileOperation: @escaping @Sendable () async throws -> AccountProfilePayload = { throw ServiceError.unconfigured("Account.myProfile") }
    ) {
        self.myProfileOperation = myProfileOperation
    }
}
