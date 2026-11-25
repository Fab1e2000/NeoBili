import NeoBiliDomain
import Foundation

extension BiliAPI {
    static func videoDetail(bvid: String, client: APIClient) async throws -> VideoDetail {
        try await client.get(
            path: "x/web-interface/view",
            params: ["bvid": bvid]
        )
    }

    /// Official iPhone ViewUnite cards include the tracking used by subsequent watch feedback.
    static func appRelatedPage(bvid: String, aid: Int = 0, entry: PlaybackEntry = .other,
                               playbackSession: String, expectedSessionID: UUID,
                               pagination: Data? = nil, client: APIClient,
                               identity: DeviceIdentity) async throws -> AppRelatedPage {
        let headers = try await identity.appRequestHeaders(expectedSessionID: expectedSessionID)
        let request = pagination.map {
            AppRelatedPage.moreRequest(bvid: bvid, aid: aid, entry: entry, playbackSession: playbackSession,
                                       accountSession: expectedSessionID, pagination: $0)
        } ?? AppRelatedPage.viewRequest(bvid: bvid, aid: aid, entry: entry,
                                       playbackSession: playbackSession, accountSession: expectedSessionID)
        let method = pagination == nil ? "View" : "RelatesFeed"
        let payload = try await client.appGRPC(path: "bilibili.app.viewunite.v1.View/" + method,
                                              payload: request, expectedSessionID: expectedSessionID, headers: headers)
        let page = try AppRelatedPage(payload: payload, isView: pagination == nil, accountSession: expectedSessionID)
        guard pagination == nil, !page.hasRelatedModule else { return page }
        // View may omit the related module for this device. Fetch the App feed once;
        // an explicitly empty module remains an empty result, and errors are not masked.
        let firstPage = AppRelatedPage.moreRequest(bvid: bvid, aid: aid, entry: entry,
            playbackSession: playbackSession, accountSession: expectedSessionID, pagination: Data())
        let related = try await client.appGRPC(path: "bilibili.app.viewunite.v1.View/RelatesFeed",
            payload: firstPage, expectedSessionID: expectedSessionID, headers: headers)
        return try AppRelatedPage(payload: related, isView: false, accountSession: expectedSessionID)
    }

    static func relatedVideos(bvid: String, client: APIClient, identity: DeviceIdentity) async throws -> [VideoSummary] {
        let login = await identity.loginSessionID
        return try await appRelatedPage(bvid: bvid, playbackSession: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(),
                                        expectedSessionID: login, client: client, identity: identity).videos
    }

    // MARK: - 视频页附加信息

    /// 网页视频详情的稿件标签。
    static func videoTags(aid: Int, client: APIClient) async throws -> [VideoTag] {
        try await client.get(
            path: "x/web-interface/view/detail/tag",
            params: ["aid": String(aid)]
        )
    }

    /// 当前账号与这个稿件的关系：点赞、投币、收藏、点踩、是否关注 UP 主。
    ///
    /// 五个按钮的高亮状态一次拿全。未登录时接口照样返回 code 0，只是全为假值，
    /// 所以调用方不需要为访客单独分支。
    static func videoRelation(aid: Int, bvid: String, client: APIClient) async throws -> VideoRelation {
        try await client.get(
            path: "x/web-interface/archive/relation",
            params: ["aid": String(aid), "bvid": bvid]
        )
    }

    /// UP 主名片，用来显示粉丝数和投稿数。`photo=false` 让服务端不必附带空间头图。
    static func memberCard(mid: Int, client: APIClient) async throws -> MemberCard {
        let payload: MemberCardPayload = try await client.get(
            path: "x/web-interface/card",
            params: ["mid": String(mid), "photo": "false"]
        )
        return MemberCard(follower: payload.follower, archiveCount: payload.archiveCount)
    }
}

/// `x/web-interface/card` 的 data 里除了名片本体，粉丝数和投稿数是平铺在
/// 顶层的（`follower` / `archive_count`），所以单独解一层再收敛成 `MemberCard`。
private struct MemberCardPayload: Decodable {
    let follower: Int?
    let archiveCount: Int?

    enum CodingKeys: String, CodingKey {
        case follower
        case archiveCount = "archive_count"
    }
}
