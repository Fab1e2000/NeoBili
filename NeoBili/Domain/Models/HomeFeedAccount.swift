import Foundation

public struct HomeFeedAccount: Equatable, Sendable {
    public let accountID: Int?
    public let hasAppCredential: Bool

    public init(
        accountID: Int? = nil,
        hasAppCredential: Bool
    ) {
        self.accountID = accountID
        self.hasAppCredential = hasAppCredential
    }

}
