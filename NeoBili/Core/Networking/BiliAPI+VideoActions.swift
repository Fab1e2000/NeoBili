import Foundation

extension BiliAPI {
    // MARK: - 视频页写操作（登录后）

    /// 点赞 / 取消点赞。`like` 传 true 是点赞，false 是取消。
    static func likeVideo(aid: Int, like: Bool) async throws {
        let csrf = await DeviceIdentity.shared.csrfToken ?? ""
        try await APIClient.shared.post(
            path: "x/web-interface/archive/like",
            form: [
                "aid": String(aid),
                "like": like ? "1" : "2",
                "csrf": csrf
            ]
        )
    }

    /// 点踩 / 取消点踩。
    ///
    /// 网页端没有这个写接口，只能走 App 端，因此它需要 `access_key`——也就是
    /// 只有扫码登录的账号能用（见 `APIClient.postApp`）。密码登录的账号调用时
    /// 会拿到 `BiliAPIError.missingAccessKey`。
    static func dislikeVideo(aid: Int, dislike: Bool) async throws {
        try await APIClient.shared.postApp(
            path: "x/v2/view/dislike",
            form: [
                "aid": String(aid),
                // 注意这个接口是反的：0 才是点踩，1 是取消点踩。传反了服务端会回
                // 65005「取消踩失败，未点踩过」，看起来像点踩功能整个不能用。
                "dislike": dislike ? "0" : "1"
            ]
        )
    }

    /// 一键三连：点赞 + 投币 + 收藏到默认收藏夹，服务端一次做完。
    ///
    /// 返回值说明这三步各自的结果——账号硬币不够时 `coin` 会是 false，
    /// 但点赞和收藏仍然成功，所以要按字段分别反映到界面上。
    static func tripleAction(aid: Int) async throws -> TripleResult {
        let csrf = await DeviceIdentity.shared.csrfToken ?? ""
        return try await APIClient.shared.post(
            path: "x/web-interface/archive/like/triple",
            form: ["aid": String(aid), "csrf": csrf]
        )
    }

    /// 投币。`multiply` 上限是 2；`selectLike` 为 true 时顺带点赞。
    static func addCoin(aid: Int, multiply: Int, selectLike: Bool = false) async throws {
        let csrf = await DeviceIdentity.shared.csrfToken ?? ""
        try await APIClient.shared.post(
            path: "x/web-interface/coin/add",
            form: [
                "aid": String(aid),
                "multiply": String(multiply),
                "select_like": selectLike ? "1" : "0",
                "csrf": csrf
            ]
        )
    }

    /// 一次性调整这个视频在各个收藏夹里的归属。
    /// 两个列表都可以为空，服务端按「加入这些、移出那些」处理。
    static func updateFavorites(aid: Int, addFolderIDs: [Int], removeFolderIDs: [Int]) async throws {
        let csrf = await DeviceIdentity.shared.csrfToken ?? ""
        try await APIClient.shared.post(
            path: "x/v3/fav/resource/deal",
            form: [
                "rid": String(aid),
                "type": "2",
                "add_media_ids": addFolderIDs.map(String.init).joined(separator: ","),
                "del_media_ids": removeFolderIDs.map(String.init).joined(separator: ","),
                "csrf": csrf
            ]
        )
    }

    /// 关注 / 取消关注 UP 主。
    ///
    /// 这个接口会校验来源站点，所以要把 Origin/Referer 换成 space 站——沿用
    /// 全站默认的 www 来源会被拒。`re_src=11` 表示来源是视频播放页。
    static func modifyRelation(mid: Int, follow: Bool) async throws {
        let csrf = await DeviceIdentity.shared.csrfToken ?? ""
        try await APIClient.shared.post(
            path: "x/relation/modify",
            form: [
                "fid": String(mid),
                "act": follow ? "1" : "2",
                "re_src": "11",
                "gaia_source": "web_main",
                "spmid": "333.788",
                "csrf": csrf
            ],
            additionalHeaders: [
                "Origin": "https://space.bilibili.com",
                "Referer": "https://space.bilibili.com/\(mid)/dynamic"
            ]
        )
    }
}
