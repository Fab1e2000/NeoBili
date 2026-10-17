#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation

extension VideoService {
    static func live(client: APIClient, identity: DeviceIdentity) -> Self {
        Self(storyboardOperation: { bvid, cid in
            try await client.get(path: "x/player/videoshot", params: ["bvid": bvid, "cid": String(cid), "index": "1"],
                                 additionalHeaders: ["Referer": "https://www.bilibili.com/video/\(bvid)"])
        },
            playURLOperation: { bvid, cid, quality in
                try await BiliAPI.playURL(bvid: bvid, cid: cid, quality: quality, client: client, identity: identity)
            },
            videoDetailOperation: { bvid in
                try await BiliAPI.videoDetail(bvid: bvid, client: client)
            },
            appRelatedPageOperation: { bvid, aid, entry, playbackSession, expectedSessionID, pagination in
                try await BiliAPI.appRelatedPage(bvid: bvid, aid: aid, entry: entry, playbackSession: playbackSession, expectedSessionID: expectedSessionID, pagination: pagination, client: client, identity: identity)
            },
            videoTagsOperation: { aid in
                try await BiliAPI.videoTags(aid: aid, client: client)
            },
            videoRelationOperation: { aid, bvid in
                try await BiliAPI.videoRelation(aid: aid, bvid: bvid, client: client)
            },
            memberCardOperation: { mid in
                try await BiliAPI.memberCard(mid: mid, client: client)
            },
            likeVideoOperation: { aid, like in
                try await BiliAPI.likeVideo(aid: aid, like: like, client: client, identity: identity)
            },
            likeVideoWithContextOperation: { aid, like, entry, expectedSessionID in
                try await BiliAPI.likeVideo(aid: aid, like: like, entry: entry, expectedSessionID: expectedSessionID, client: client)
            },
            dislikeVideoOperation: { aid, dislike, entry, expectedSessionID in
                try await BiliAPI.dislikeVideo(aid: aid, dislike: dislike, entry: entry, expectedSessionID: expectedSessionID, client: client)
            },
            tripleActionOperation: { aid, entry, expectedSessionID in
                try await BiliAPI.tripleAction(aid: aid, entry: entry, expectedSessionID: expectedSessionID, client: client)
            },
            addCoinOperation: { aid, multiply, selectLike, entry, expectedSessionID in
                try await BiliAPI.addCoin(aid: aid, multiply: multiply, selectLike: selectLike, entry: entry, expectedSessionID: expectedSessionID, client: client)
            },
            updateFavoritesOperation: { aid, addFolderIDs, removeFolderIDs, expectedSessionID in
                try await BiliAPI.updateFavorites(aid: aid, addFolderIDs: addFolderIDs, removeFolderIDs: removeFolderIDs, expectedSessionID: expectedSessionID, client: client, identity: identity)
            },
            blockUserOperation: { mid in
                try await BiliAPI.blockUser(mid: mid, client: client, identity: identity)
            },
            modifyRelationOperation: { mid, follow in
                try await BiliAPI.modifyRelation(mid: mid, follow: follow, client: client, identity: identity)
            }
        )
    }
}
