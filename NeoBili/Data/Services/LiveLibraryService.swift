#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation

extension LibraryService {
    static func live(client: APIClient, identity: DeviceIdentity) -> Self {
        Self(
            historyPageOperation: { max, viewAt in
                try await BiliAPI.historyPage(max: max, viewAt: viewAt, client: client)
            },
            reportWatchProgressOperation: { bvid, cid, playedTime, expectedSessionID in
                try await BiliAPI.reportWatchProgress(bvid: bvid, cid: cid, playedTime: playedTime, expectedSessionID: expectedSessionID, client: client, identity: identity)
            },
            deleteHistoryOperation: { kid, expectedSessionID in
                try await BiliAPI.deleteHistory(kid: kid, expectedSessionID: expectedSessionID, client: client, identity: identity)
            },
            reportAppWatchOperation: { bvid, aid, cid, report, expectedSessionID in
                try await BiliAPI.reportAppWatch(bvid: bvid, aid: aid, cid: cid, report: report, expectedSessionID: expectedSessionID, client: client, identity: identity)
            },
            favoriteFoldersOperation: { ownerMid, videoAid in
                try await BiliAPI.favoriteFolders(ownerMid: ownerMid, videoAid: videoAid, client: client)
            },
            favoriteVideosOperation: { folderID, page in
                try await BiliAPI.favoriteVideos(folderID: folderID, page: page, client: client)
            },
            removeFavoriteOperation: { folderID, aid, expectedSessionID in
                try await BiliAPI.removeFavorite(folderID: folderID, aid: aid, expectedSessionID: expectedSessionID, client: client, identity: identity)
            },
            unfavoriteEverywhereOperation: { aid in
                try await BiliAPI.unfavoriteEverywhere(aid: aid, client: client, identity: identity)
            },
            deleteFavoriteFoldersOperation: { folderIDs, expectedSessionID in
                try await BiliAPI.deleteFavoriteFolders(folderIDs: folderIDs, expectedSessionID: expectedSessionID, client: client, identity: identity)
            },
            addWatchLaterOperation: { aid, bvid in
                try await BiliAPI.addWatchLater(aid: aid, bvid: bvid, client: client, identity: identity)
            },
            watchLaterPageOperation: { startKey, splitKey, expectedSessionID in
                try await BiliAPI.watchLaterPage(startKey: startKey, splitKey: splitKey, expectedSessionID: expectedSessionID, client: client)
            },
            removeWatchLaterOperation: { aid, expectedSessionID in
                try await BiliAPI.removeWatchLater(aid: aid, expectedSessionID: expectedSessionID, client: client, identity: identity)
            }
        )
    }
}
