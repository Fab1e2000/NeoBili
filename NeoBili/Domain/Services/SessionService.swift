import Foundation

struct SessionService: Sendable {
    var currentID: @Sendable () -> UUID
    var homeAccount: @Sendable () async -> HomeFeedAccount
}
