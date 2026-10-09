import Foundation

extension CommunityService {
    static func live(client: APIClient = .shared) -> Self {
        Self(
            dynamicVoteInfoOperation: { id in
                try await BiliAPI.dynamicVoteInfo(id: id)
            },
            submitDynamicVoteOperation: { id, options, voterMID, dynamicID in
                try await BiliAPI.submitDynamicVote(id: id, options: options, voterMID: voterMID, dynamicID: dynamicID)
            },
            followedUpsOperation: {
                try await BiliAPI.followedUps()
            },
            followingsOperation: { mid, page in
                try await BiliAPI.followings(mid: mid, page: page)
            },
            followedDynamicsOperation: { page, offset, hostMid in
                try await BiliAPI.followedDynamics(page: page, offset: offset, hostMid: hostMid)
            },
            dynamicDetailOperation: { id in
                try await BiliAPI.dynamicDetail(id: id)
            },
            spaceDynamicsOperation: { hostMid, offset in
                try await BiliAPI.spaceDynamics(hostMid: hostMid, offset: offset)
            },
            likeDynamicOperation: { id, like in
                try await BiliAPI.likeDynamic(id: id, like: like)
            },
            spaceCardOperation: { mid in
                try await BiliAPI.spaceCard(mid: mid, client: client)
            },
            spaceProfileOperation: { mid in
                try await BiliAPI.spaceProfile(mid: mid, client: client)
            },
            spaceVideosOperation: { mid, page in
                try await BiliAPI.spaceVideos(mid: mid, page: page)
            }
        )
    }
}
