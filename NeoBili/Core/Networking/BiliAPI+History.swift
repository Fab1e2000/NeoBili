import Foundation

extension BiliAPI {
    /// 观看历史按游标翻页：首页 max=0 / view_at=0，之后带上上一页返回的游标。
    static func historyPage(max: Int, viewAt: Int) async throws -> HistoryCursorPage {
        try await APIClient.shared.get(
            path: "x/web-interface/history/cursor",
            params: [
                "type": "archive",
                "ps": "20",
                "max": String(max),
                "view_at": String(viewAt)
            ]
        )
    }

    /// 上报观看进度（心跳）。历史记录页的数据源就是它：不报的话，
    /// 在本 App 里看过的视频永远不会出现在 B 站的观看历史里。
    ///
    /// 格式对齐 PiliPlus：UGC 稿件 type=3，`played_time` 传秒数，
    /// 看完时传 -1。未登录（拿不到 csrf）时直接不发。
    static func reportWatchProgress(bvid: String, cid: Int, playedTime: Double) async throws {
        guard let csrf = await DeviceIdentity.shared.csrfToken, !csrf.isEmpty else { return }
        try await APIClient.shared.post(
            path: "x/click-interface/web/heartbeat",
            form: [
                "bvid": bvid,
                "cid": String(cid),
                "type": "3",
                "played_time": String(Int(playedTime.rounded())),
                "csrf": csrf
            ]
        )
    }

    /// 删除单条观看历史。
    ///
    /// 端点是 `x/v2/history/delete`——之前写成了 `x/web-interface/history/del`，
    /// 那个路径根本不存在，所以返回的是 HTTP 404 而不是业务错误码。
    static func deleteHistory(kid: String) async throws {
        let csrf = await DeviceIdentity.shared.csrfToken ?? ""
        try await APIClient.shared.post(
            path: "x/v2/history/delete",
            form: ["kid": kid, "jsonp": "jsonp", "csrf": csrf]
        )
    }
}
