import Foundation

extension BiliAPI {
    // MARK: - 关注（动态）

    /// 动态页顶上那一排关注的 UP 主，附带「有没有更新」用来画小红点。
    /// 未登录时接口直接回 -101，由调用方转成登录提示。
    static func dynamicVoteInfo(id: Int) async throws -> DynamicVoteResponse {
        try await APIClient.shared.get(path: "x/vote/vote_info", params: ["vote_id": String(id)])
    }

    static func submitDynamicVote(id: Int, options: [Int], voterMID: Int, dynamicID: String) async throws {
        let csrf = await DeviceIdentity.shared.csrfToken ?? ""
        try await APIClient.shared.postJSON(
            path: "x/vote/do_vote",
            query: ["csrf": csrf],
            json: ["vote_id": id, "votes": options, "voter_uid": voterMID,
                   "status": 0, "op_bit": 0, "dynamic_id": Int(dynamicID) ?? 0,
                   "csrf": csrf, "csrf_token": csrf]
        )
    }

    static func followedUps() async throws -> [FollowedUp] {
        let payload: DynamicPortalPayload = try await APIClient.shared.get(
            path: "x/polymer/web-dynamic/v1/portal",
            params: ["web_location": "333.1365"],
            additionalHeaders: DynamicRequest.headers
        )
        return payload.upList ?? []
    }

    /// 自己关注的全部 UP 主，按关注时间倒序分页，每页 50 个。
    static func followings(mid: Int, page: Int) async throws -> FollowingsPage {
        try await APIClient.shared.get(
            path: "x/relation/followings",
            params: ["vmid": String(mid), "pn": String(page), "ps": String(FollowingsPage.pageSize), "order": "desc"]
        )
    }

    /// 关注的 UP 主的动态。
    ///
    /// `type=all` 把视频投稿、纯文字、图文都取回来（转发、直播预约这些由
    /// `DynamicEntry` 那一层过滤掉）。翻页用的是上一页返回的 `offset` 游标
    /// 而不是页码，`page` 只是给服务端做统计；第一页不传 offset。
    ///
    /// 传 `hostMid` 时只取这一位关注 UP 主的动态，等同网页动态页点头像：
    /// 服务端据此清除他在 portal 头像列表里的 `has_update` 红点（与 PiliPlus 一致）。
    static func followedDynamics(page: Int, offset: String?, hostMid: Int? = nil) async throws -> DynamicFeedPage {
        var params = [
            "timezone_offset": "-480",
            "platform": "web",
            "features": "itemOpusStyle",
            "page": String(page),
            "web_location": "333.1365"
        ]
        if let hostMid {
            params["host_mid"] = String(hostMid)
        } else {
            params["type"] = "all"
        }
        if let offset, !offset.isEmpty {
            params["offset"] = offset
        }
        return try await APIClient.shared.get(
            path: "x/polymer/web-dynamic/v1/feed/all",
            params: params,
            additionalHeaders: DynamicRequest.headers
        )
    }

    /// 某个 UP 主自己的动态。结构和关注流完全一样，只是换了个端点。
    static func spaceDynamics(hostMid: Int, offset: String?) async throws -> DynamicFeedPage {
        var params = [
            "host_mid": String(hostMid),
            "timezone_offset": "-480",
            "platform": "web",
            "features": "itemOpusStyle",
            "web_location": "333.999"
        ]
        if let offset, !offset.isEmpty {
            params["offset"] = offset
        }
        return try await APIClient.shared.get(
            path: "x/polymer/web-dynamic/v1/feed/space",
            params: params,
            additionalHeaders: DynamicRequest.headers
        )
    }

    /// 给动态点赞 / 取消点赞。`up` 传 1 是点赞，2 是取消。
    ///
    /// 该接口只认 JSON body：表单编码会报 4100001 参数错误。csrf 按惯例
    /// 放 query，body 里带 spmid（对齐 PiliPlus 的请求格式）。
    static func likeDynamic(id: String, like: Bool) async throws {
        let csrf = await DeviceIdentity.shared.csrfToken ?? ""
        try await APIClient.shared.postJSON(
            path: "x/dynamic/feed/dyn/thumb",
            query: ["csrf": csrf],
            json: [
                "dyn_id_str": id,
                "up": like ? 1 : 2,
                "spmid": "333.1365.0.0"
            ],
            additionalHeaders: DynamicRequest.headers
        )
    }
}

/// 动态接口会校验来源站点，来源要写成动态站而不是全站默认的 www。
enum DynamicRequest {
    static let headers = [
        "Origin": "https://t.bilibili.com",
        "Referer": "https://t.bilibili.com/"
    ]
}
