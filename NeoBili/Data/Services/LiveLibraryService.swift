import Foundation

extension LibraryService {
    static func live(client: APIClient = .shared) -> Self {
        Self(
            historyPageOperation: { max, viewAt in
                try await BiliAPI.historyPage(max: max, viewAt: viewAt)
            },
            reportWatchProgressOperation: { bvid, cid, playedTime, expectedSessionID in
                try await BiliAPI.reportWatchProgress(bvid: bvid, cid: cid, playedTime: playedTime, expectedSessionID: expectedSessionID, client: client)
            },
            deleteHistoryOperation: { kid, expectedSessionID in
                try await BiliAPI.deleteHistory(kid: kid, expectedSessionID: expectedSessionID)
            },
            reportAppWatchOperation: { bvid, aid, cid, report, expectedSessionID in
                try await BiliAPI.reportAppWatch(bvid: bvid, aid: aid, cid: cid, report: report, expectedSessionID: expectedSessionID, client: client)
            },
            favoriteFoldersOperation: { ownerMid, videoAid in
                try await BiliAPI.favoriteFolders(ownerMid: ownerMid, videoAid: videoAid)
            },
            favoriteVideosOperation: { folderID, page in
                try await BiliAPI.favoriteVideos(folderID: folderID, page: page)
            },
            removeFavoriteOperation: { folderID, aid, expectedSessionID in
                try await BiliAPI.removeFavorite(folderID: folderID, aid: aid, expectedSessionID: expectedSessionID)
            },
            unfavoriteEverywhereOperation: { aid in
                try await BiliAPI.unfavoriteEverywhere(aid: aid)
            },
            deleteFavoriteFoldersOperation: { folderIDs, expectedSessionID in
                try await BiliAPI.deleteFavoriteFolders(folderIDs: folderIDs, expectedSessionID: expectedSessionID, client: client)
            },
            addWatchLaterOperation: { aid, bvid in
                try await BiliAPI.addWatchLater(aid: aid, bvid: bvid)
            },
            watchLaterPageOperation: { startKey, splitKey, expectedSessionID in
                try await BiliAPI.watchLaterPage(startKey: startKey, splitKey: splitKey, expectedSessionID: expectedSessionID, client: client)
            },
            removeWatchLaterOperation: { aid, expectedSessionID in
                try await BiliAPI.removeWatchLater(aid: aid, expectedSessionID: expectedSessionID)
            }
        )
    }
}
