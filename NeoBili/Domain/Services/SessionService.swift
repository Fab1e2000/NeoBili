import Foundation

public struct SessionService: Sendable {
    public var currentID: @Sendable () -> UUID
    public var homeAccount: @Sendable () async -> HomeFeedAccount

    public init(
        currentID: @escaping @Sendable () -> UUID,
        homeAccount: @escaping @Sendable () async -> HomeFeedAccount
    ) {
        self.currentID = currentID
        self.homeAccount = homeAccount
    }
}
