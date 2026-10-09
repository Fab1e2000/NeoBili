import Foundation

/// Account operations available to application state and views.
/// Values can be replaced per model or view hierarchy without changing global state.
struct AccountService: Sendable {
    var myProfileOperation: @Sendable () async throws -> AccountProfilePayload = { throw ServiceError.unconfigured("Account.myProfile") }

    func myProfile() async throws -> AccountProfilePayload {
        try await myProfileOperation()
    }
}
