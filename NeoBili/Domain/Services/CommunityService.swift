import Foundation

/// Community operations available to application state and views.
/// Values can be replaced per model or view hierarchy without changing global state.
public struct CommunityService: Sendable {
    public var dynamicVoteInfoOperation: @Sendable (Int) async throws -> DynamicVoteResponse = { _ in throw ServiceError.unconfigured("Community.dynamicVoteInfo") }
    public var submitDynamicVoteOperation: @Sendable (Int, [Int], Int, String) async throws -> Void = { _, _, _, _ in throw ServiceError.unconfigured("Community.submitDynamicVote") }
    public var followedUpsOperation: @Sendable () async throws -> [FollowedUp] = { throw ServiceError.unconfigured("Community.followedUps") }
    public var followingsOperation: @Sendable (Int, Int) async throws -> FollowingsPage = { _, _ in throw ServiceError.unconfigured("Community.followings") }
    public var followedDynamicsOperation: @Sendable (Int, String?, Int?) async throws -> DynamicFeedPage = { _, _, _ in throw ServiceError.unconfigured("Community.followedDynamics") }
    public var dynamicDetailOperation: @Sendable (String) async throws -> DynamicItem = { _ in throw ServiceError.unconfigured("Community.dynamicDetail") }
    public var spaceDynamicsOperation: @Sendable (Int, String?) async throws -> DynamicFeedPage = { _, _ in throw ServiceError.unconfigured("Community.spaceDynamics") }
    public var likeDynamicOperation: @Sendable (String, Bool) async throws -> Void = { _, _ in throw ServiceError.unconfigured("Community.likeDynamic") }
    public var spaceCardOperation: @Sendable (Int) async throws -> SpaceCard = { _ in throw ServiceError.unconfigured("Community.spaceCard") }
    public var spaceProfileOperation: @Sendable (Int) async throws -> SpaceCard = { _ in throw ServiceError.unconfigured("Community.spaceProfile") }
    public var spaceVideosOperation: @Sendable (Int, Int) async throws -> SpaceVideoPage = { _, _ in throw ServiceError.unconfigured("Community.spaceVideos") }

    public func dynamicVoteInfo(id: Int) async throws -> DynamicVoteResponse {
        try await dynamicVoteInfoOperation(id)
    }

    public func submitDynamicVote(id: Int, options: [Int], voterMID: Int, dynamicID: String) async throws {
        try await submitDynamicVoteOperation(id, options, voterMID, dynamicID)
    }

    public func followedUps() async throws -> [FollowedUp] {
        try await followedUpsOperation()
    }

    public func followings(mid: Int, page: Int) async throws -> FollowingsPage {
        try await followingsOperation(mid, page)
    }

    public func followedDynamics(page: Int, offset: String?, hostMid: Int? = nil) async throws -> DynamicFeedPage {
        try await followedDynamicsOperation(page, offset, hostMid)
    }

    public func dynamicDetail(id: String) async throws -> DynamicItem {
        try await dynamicDetailOperation(id)
    }

    public func spaceDynamics(hostMid: Int, offset: String?) async throws -> DynamicFeedPage {
        try await spaceDynamicsOperation(hostMid, offset)
    }

    public func likeDynamic(id: String, like: Bool) async throws {
        try await likeDynamicOperation(id, like)
    }

    public func spaceCard(mid: Int) async throws -> SpaceCard {
        try await spaceCardOperation(mid)
    }

    public func spaceProfile(mid: Int) async throws -> SpaceCard {
        try await spaceProfileOperation(mid)
    }

    public func spaceVideos(mid: Int, page: Int) async throws -> SpaceVideoPage {
        try await spaceVideosOperation(mid, page)
    }

    public init(
        dynamicVoteInfoOperation: @escaping @Sendable (Int) async throws -> DynamicVoteResponse = { _ in throw ServiceError.unconfigured("Community.dynamicVoteInfo") },
        submitDynamicVoteOperation: @escaping @Sendable (Int, [Int], Int, String) async throws -> Void = { _, _, _, _ in throw ServiceError.unconfigured("Community.submitDynamicVote") },
        followedUpsOperation: @escaping @Sendable () async throws -> [FollowedUp] = { throw ServiceError.unconfigured("Community.followedUps") },
        followingsOperation: @escaping @Sendable (Int, Int) async throws -> FollowingsPage = { _, _ in throw ServiceError.unconfigured("Community.followings") },
        followedDynamicsOperation: @escaping @Sendable (Int, String?, Int?) async throws -> DynamicFeedPage = { _, _, _ in throw ServiceError.unconfigured("Community.followedDynamics") },
        dynamicDetailOperation: @escaping @Sendable (String) async throws -> DynamicItem = { _ in throw ServiceError.unconfigured("Community.dynamicDetail") },
        spaceDynamicsOperation: @escaping @Sendable (Int, String?) async throws -> DynamicFeedPage = { _, _ in throw ServiceError.unconfigured("Community.spaceDynamics") },
        likeDynamicOperation: @escaping @Sendable (String, Bool) async throws -> Void = { _, _ in throw ServiceError.unconfigured("Community.likeDynamic") },
        spaceCardOperation: @escaping @Sendable (Int) async throws -> SpaceCard = { _ in throw ServiceError.unconfigured("Community.spaceCard") },
        spaceProfileOperation: @escaping @Sendable (Int) async throws -> SpaceCard = { _ in throw ServiceError.unconfigured("Community.spaceProfile") },
        spaceVideosOperation: @escaping @Sendable (Int, Int) async throws -> SpaceVideoPage = { _, _ in throw ServiceError.unconfigured("Community.spaceVideos") }
    ) {
        self.dynamicVoteInfoOperation = dynamicVoteInfoOperation
        self.submitDynamicVoteOperation = submitDynamicVoteOperation
        self.followedUpsOperation = followedUpsOperation
        self.followingsOperation = followingsOperation
        self.followedDynamicsOperation = followedDynamicsOperation
        self.dynamicDetailOperation = dynamicDetailOperation
        self.spaceDynamicsOperation = spaceDynamicsOperation
        self.likeDynamicOperation = likeDynamicOperation
        self.spaceCardOperation = spaceCardOperation
        self.spaceProfileOperation = spaceProfileOperation
        self.spaceVideosOperation = spaceVideosOperation
    }
}
