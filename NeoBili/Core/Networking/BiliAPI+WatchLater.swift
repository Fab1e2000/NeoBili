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

    /// 移出稍后再看。
    static func removeWatchLater(aid: Int) async throws {
        let csrf = await DeviceIdentity.shared.csrfToken ?? ""
        try await APIClient.shared.post(
            path: "x/v2/history/toview/del",
            form: ["aid": String(aid), "csrf": csrf]
        )
    }
}
