import Foundation

extension BiliAPI {
    /// 自己创建的收藏夹列表（含默认收藏夹）。
    /// `list-all` 的 data 是 `{"count": N, "list": [...]}`，不是裸数组。
    ///
    /// 传了 `videoAid` 时每个收藏夹会多带一个 `fav_state`，表示它里面有没有
    /// 这个视频——收藏夹选择弹窗靠它决定默认勾选哪几项，不必逐个收藏夹去查。
    static func favoriteFolders(ownerMid: Int, videoAid: Int? = nil) async throws -> [FavFolder] {
        var params = ["up_mid": String(ownerMid)]
        if let videoAid {
            params["type"] = "2"
            params["rid"] = String(videoAid)
        }
        let payload: FavFolderList = try await APIClient.shared.get(
            path: "x/v3/fav/folder/created/list-all",
            params: params
        )
        return payload.list ?? []
    }

    static func favoriteVideos(folderID: Int, page: Int) async throws -> FavResourceList {
        try await APIClient.shared.get(
            path: "x/v3/fav/resource/list",
            params: [
                "media_id": String(folderID),
                "pn": String(page),
                "ps": "20",
                "order": "mtime",
                "platform": "web"
            ]
        )
    }

    /// 从某个收藏夹里取消收藏。
    ///
    /// 走的就是下面那个 `updateFavorites`——`deal` 接口只认 `add_media_ids` 和
    /// `del_media_ids` 两个字段。这里以前写的是 `remove_media_ids`，服务端认不出
    /// 来，于是每次都返回成功却什么也没删，表现就是「取消收藏没反应」。
    static func removeFavorite(folderID: Int, aid: Int) async throws {
        try await updateFavorites(aid: aid, addFolderIDs: [], removeFolderIDs: [folderID])
    }

    /// 把稿件从**所有**收藏夹里移除。收藏按钮在已收藏状态下再点一次走这里。
    static func unfavoriteEverywhere(aid: Int) async throws {
        let csrf = await DeviceIdentity.shared.csrfToken ?? ""
        try await APIClient.shared.post(
            path: "x/v3/fav/resource/unfav-all",
            form: ["rid": String(aid), "type": "2", "csrf": csrf]
        )
    }

    /// 删除整个收藏夹。可以一次删多个，服务端要求逗号分隔。
    static func deleteFavoriteFolders(folderIDs: [Int]) async throws {
        let csrf = await DeviceIdentity.shared.csrfToken ?? ""
        try await APIClient.shared.post(
            path: "x/v3/fav/folder/del",
            form: [
                "media_ids": folderIDs.map(String.init).joined(separator: ","),
                "platform": "web",
                "csrf": csrf
            ]
        )
    }
}
