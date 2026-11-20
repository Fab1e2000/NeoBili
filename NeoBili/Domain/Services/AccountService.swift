import Foundation

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
