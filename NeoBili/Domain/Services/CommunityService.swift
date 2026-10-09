import Foundation

/// Community operations available to application state and views.
/// Values can be replaced per model or view hierarchy without changing global state.
struct CommunityService: Sendable {
    var dynamicVoteInfoOperation: @Sendable (Int) async throws -> DynamicVoteResponse = { _ in throw ServiceError.unconfigured("Community.dynamicVoteInfo") }
    var submitDynamicVoteOperation: @Sendable (Int, [Int], Int, String) async throws -> Void = { _, _, _, _ in throw ServiceError.unconfigured("Community.submitDynamicVote") }
    var followedUpsOperation: @Sendable () async throws -> [FollowedUp] = { throw ServiceError.unconfigured("Community.followedUps") }
    var followingsOperation: @Sendable (Int, Int) async throws -> FollowingsPage = { _, _ in throw ServiceError.unconfigured("Community.followings") }
    var followedDynamicsOperation: @Sendable (Int, String?, Int?) async throws -> DynamicFeedPage = { _, _, _ in throw ServiceError.unconfigured("Community.followedDynamics") }
    var dynamicDetailOperation: @Sendable (String) async throws -> DynamicItem = { _ in throw ServiceError.unconfigured("Community.dynamicDetail") }
    var spaceDynamicsOperation: @Sendable (Int, String?) async throws -> DynamicFeedPage = { _, _ in throw ServiceError.unconfigured("Community.spaceDynamics") }
    var likeDynamicOperation: @Sendable (String, Bool) async throws -> Void = { _, _ in throw ServiceError.unconfigured("Community.likeDynamic") }
    var spaceCardOperation: @Sendable (Int) async throws -> SpaceCard = { _ in throw ServiceError.unconfigured("Community.spaceCard") }
    var spaceProfileOperation: @Sendable (Int) async throws -> SpaceCard = { _ in throw ServiceError.unconfigured("Community.spaceProfile") }
    var spaceVideosOperation: @Sendable (Int, Int) async throws -> SpaceVideoPage = { _, _ in throw ServiceError.unconfigured("Community.spaceVideos") }

    func dynamicVoteInfo(id: Int) async throws -> DynamicVoteResponse {
        try await dynamicVoteInfoOperation(id)
    }

    func submitDynamicVote(id: Int, options: [Int], voterMID: Int, dynamicID: String) async throws {
        try await submitDynamicVoteOperation(id, options, voterMID, dynamicID)
    }

    func followedUps() async throws -> [FollowedUp] {
        try await followedUpsOperation()
    }

    func followings(mid: Int, page: Int) async throws -> FollowingsPage {
        try await followingsOperation(mid, page)
    }

    func followedDynamics(page: Int, offset: String?, hostMid: Int? = nil) async throws -> DynamicFeedPage {
        try await followedDynamicsOperation(page, offset, hostMid)
    }

    func dynamicDetail(id: String) async throws -> DynamicItem {
        try await dynamicDetailOperation(id)
    }

    func spaceDynamics(hostMid: Int, offset: String?) async throws -> DynamicFeedPage {
        try await spaceDynamicsOperation(hostMid, offset)
    }

    func likeDynamic(id: String, like: Bool) async throws {
        try await likeDynamicOperation(id, like)
    }

    func spaceCard(mid: Int) async throws -> SpaceCard {
        try await spaceCardOperation(mid)
    }

    func spaceProfile(mid: Int) async throws -> SpaceCard {
        try await spaceProfileOperation(mid)
    }

    func spaceVideos(mid: Int, page: Int) async throws -> SpaceVideoPage {
        try await spaceVideosOperation(mid, page)
    }
}
