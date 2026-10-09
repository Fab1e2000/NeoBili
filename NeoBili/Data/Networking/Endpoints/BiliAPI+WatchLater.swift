import Foundation

extension BiliAPI {
    /// 加入稍后再看。avid 和 bvid 给一个就行——搜索结果只有 bvid。
    static func addWatchLater(aid: Int?, bvid: String?) async throws {
        let csrf = await DeviceIdentity.shared.csrfToken ?? ""
        var form = ["csrf": csrf]
        if let aid { form["aid"] = String(aid) }
        if let bvid { form["bvid"] = bvid }
        try await APIClient.shared.post(path: "x/v2/history/toview/add", form: form)
    }

    static func watchLaterList() async throws -> WatchLaterPage {
        try await APIClient.shared.get(path: "x/v2/history/toview")
    }

    static func watchLaterPage(startKey: String, splitKey: String, expectedSessionID: UUID, client: APIClient = .shared) async throws -> WatchLaterListPage {
        let page: WatchLaterV2Page = try await client.getApp(
            path: "x/v2/history/toview/v2/list",
            params: ["start_key": startKey, "split_key": splitKey, "asc": "false", "sort_field": "1"],
            expectedSessionID: expectedSessionID, requiresAccountCredential: true, usesAPIHost: true)
        return .init(items: page.list, nextKey: page.nextKey, splitKey: page.splitKey, hasMore: page.hasMore)
    }

    /// 移出稍后再看。
    static func removeWatchLater(aid: Int, expectedSessionID: UUID? = nil) async throws {
        let csrf = await DeviceIdentity.shared.csrfToken ?? ""
        try await APIClient.shared.post(
            path: "x/v2/history/toview/del",
            form: ["aid": String(aid), "csrf": csrf],
            expectedSessionID: expectedSessionID
        )
    }
}

/// Official 9.13 capture confirms core item keys match the existing video model.
private struct WatchLaterV2Page: Decodable {
    let list: [WatchLaterItem]
    let hasMore: Bool
    let nextKey: String
    let splitKey: String
    enum CodingKeys: String, CodingKey {
        case list
        case hasMore = "has_more", nextKey = "next_key", splitKey = "split_key"
    }
}
