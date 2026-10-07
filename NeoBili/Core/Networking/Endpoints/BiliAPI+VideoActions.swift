import Foundation

extension BiliAPI {
    // MARK: - 视频页写操作（登录后）

    /// ACT-01: send only the three tracker fields consumed by the official UGC action.
    static func videoActionParameters(aid: Int, entry: PlaybackEntry,
                                      sessionID: UUID?) throws -> [String: String] {
        if let origin = entry.loginSessionID, origin != sessionID { throw CancellationError() }
        let source = entry.parameters(for: sessionID)
        return ["aid": String(aid), "from": source["from"] ?? "",
                "from_spmid": source["from_spmid"] ?? "",
                "spmid": "united.player-video-detail.0.0"]
    }

    /// Existing dynamic-feed interaction: its App tracker has not been established yet.
    static func likeVideo(aid: Int, like: Bool) async throws {
        let csrf = await DeviceIdentity.shared.csrfToken ?? ""
        try await APIClient.shared.post(path: "x/web-interface/archive/like",
            form: ["aid": String(aid), "like": like ? "1" : "2", "csrf": csrf])
    }

    /// App like is the target state: 1 likes, 0 removes the like (web uses 2).
    static func likeVideo(aid: Int, like: Bool, entry: PlaybackEntry,
                          expectedSessionID: UUID? = nil, client: APIClient = .shared) async throws {
        let account = try await client.appAccount(expectedSessionID: expectedSessionID)
        var form = try videoActionParameters(aid: aid, entry: entry, sessionID: account.sessionID)
        form["like"] = like ? "1" : "0"
        try await client.postApp(path: "x/v2/view/like", form: form, expectedSessionID: account.sessionID)
    }

    /// App 点踩发送操作前的状态：目标点踩为 0，目标取消为 1。
    /// 独立播放器 provider 仅接收 spmid/from_spmid，不接收 from 或卡片 track_id。
    /// action_id 来自官方 pvUniqueID，未证实等同于本地 playback session，暂不伪造。
    static func dislikeVideo(aid: Int, dislike: Bool, entry: PlaybackEntry? = nil,
                             expectedSessionID: UUID? = nil, client: APIClient = .shared) async throws {
        let account = try await client.appAccount(expectedSessionID: expectedSessionID)
        var form = ["aid": String(aid), "dislike": dislike ? "0" : "1"]
        if let entry {
            let context = try videoActionParameters(aid: aid, entry: entry, sessionID: account.sessionID)
            form["spmid"] = context["spmid"]
            form["from_spmid"] = context["from_spmid"]
        }
        try await client.postApp(path: "x/v2/view/dislike", form: form, expectedSessionID: account.sessionID)
    }

    /// 一键三连：点赞 + 投币 + 收藏到默认收藏夹，服务端一次做完。
    ///
    /// 返回值说明这三步各自的结果——账号硬币不够时 `coin` 会是 false，
    /// 但点赞和收藏仍然成功，所以要按字段分别反映到界面上。
    static func tripleAction(aid: Int, entry: PlaybackEntry = .other,
                             expectedSessionID: UUID? = nil, client: APIClient = .shared) async throws -> TripleResult {
        let account = try await client.appAccount(expectedSessionID: expectedSessionID)
        let form = try videoActionParameters(aid: aid, entry: entry, sessionID: account.sessionID)
        return try await client.postAppData(path: "x/v2/view/like/triple", form: form,
            expectedSessionID: account.sessionID, usesAPIHost: false, headers: [:])
    }

    /// The current UI selects one coin; preserve an explicit two-coin choice for callers.
    static func addCoin(aid: Int, multiply: Int, selectLike: Bool = false,
                        entry: PlaybackEntry = .other, expectedSessionID: UUID? = nil,
                        client: APIClient = .shared) async throws {
        let account = try await client.appAccount(expectedSessionID: expectedSessionID)
        var form = try videoActionParameters(aid: aid, entry: entry, sessionID: account.sessionID)
        form["multiply"] = String(multiply)
        form["avtype"] = "1"
        form["select_like"] = selectLike ? "1" : "0"
        try await client.postApp(path: "x/v2/view/coin/add", form: form, expectedSessionID: account.sessionID)
    }

    /// 一次性调整这个视频在各个收藏夹里的归属。
    /// 两个列表都可以为空，服务端按「加入这些、移出那些」处理。
    static func updateFavorites(aid: Int, addFolderIDs: [Int], removeFolderIDs: [Int], expectedSessionID: UUID? = nil) async throws {
        let csrf = await DeviceIdentity.shared.csrfToken ?? ""
        try await APIClient.shared.post(
            path: "x/v3/fav/resource/deal",
            form: [
                "rid": String(aid),
                "type": "2",
                "add_media_ids": addFolderIDs.map(String.init).joined(separator: ","),
                "del_media_ids": removeFolderIDs.map(String.init).joined(separator: ","),
                "csrf": csrf
            ], expectedSessionID: expectedSessionID
        )
    }

    /// 拉黑 UP 主。参数照 PiliPlus `VideoHttp.relationMod`（act=5）。
    static func blockUser(mid: Int) async throws {
        let csrf = await DeviceIdentity.shared.csrfToken ?? ""
        try await APIClient.shared.post(
            path: "x/relation/modify",
            form: [
                "fid": String(mid),
                "act": "5",
                "re_src": "11",
                "gaia_source": "web_main",
                "spmid": "333.1387",
                "csrf": csrf
            ],
            additionalHeaders: [
                "Origin": "https://space.bilibili.com",
                "Referer": "https://space.bilibili.com/\(mid)/dynamic"
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
