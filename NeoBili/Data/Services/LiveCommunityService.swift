import Foundation

extension CommunityService {
    static func live(client: APIClient = .shared, identity: DeviceIdentity = .shared) -> Self {
        Self(
            dynamicVoteInfoOperation: { id in
                try await BiliAPI.dynamicVoteInfo(id: id, client: client)
            },
            submitDynamicVoteOperation: { id, options, voterMID, dynamicID in
                try await BiliAPI.submitDynamicVote(id: id, options: options, voterMID: voterMID, dynamicID: dynamicID, client: client, identity: identity)
            },
            followedUpsOperation: {
                try await BiliAPI.followedUps(client: client)
            },
            followingsOperation: { mid, page in
                try await BiliAPI.followings(mid: mid, page: page, client: client)
            },
            followedDynamicsOperation: { page, offset, hostMid in
                try await BiliAPI.followedDynamics(page: page, offset: offset, hostMid: hostMid, client: client)
            },
            dynamicDetailOperation: { id in
                try await BiliAPI.dynamicDetail(id: id, client: client)
            },
            spaceDynamicsOperation: { hostMid, offset in
                try await BiliAPI.spaceDynamics(hostMid: hostMid, offset: offset, client: client)
            },
            likeDynamicOperation: { id, like in
                try await BiliAPI.likeDynamic(id: id, like: like, client: client, identity: identity)
            },
            spaceCardOperation: { mid in
                try await BiliAPI.spaceCard(mid: mid, client: client)
            },
            spaceProfileOperation: { mid in
                try await BiliAPI.spaceProfile(mid: mid, client: client)
            },
            spaceVideosOperation: { mid, page in
                try await BiliAPI.spaceVideos(mid: mid, page: page, client: client)
            }
        )
    }
}
