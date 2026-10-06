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
    static func reportWatchProgress(bvid: String, cid: Int, playedTime: Double,
                                    expectedSessionID: UUID, client: APIClient = .shared,
                                    identity: DeviceIdentity = .shared) async throws {
        guard !bvid.isEmpty, cid > 0, playedTime.isFinite,
              playedTime == -1 || (playedTime >= 1 && playedTime < Double(Int.max)) else { return }
        let account = await identity.authenticatedRequestSnapshot()
        guard account.sessionID == expectedSessionID, account.isLoggedIn,
              let csrf = account.csrfToken, !csrf.isEmpty else { return }
        try await client.post(
            path: "x/click-interface/web/heartbeat",
            form: [
                "bvid": bvid,
                "cid": String(cid),
                "type": "3",
                "played_time": String(Int(playedTime.rounded(.down))),
                "csrf": csrf
            ],
            expectedSessionID: expectedSessionID
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

extension PlaybackWatchReport {
    var mobileParameters: [String: String] { AppWatchProtocol.mobileParameters(self) }
}

extension BiliAPI {
    /// App 授权存在时使用移动心跳与独立历史同步，不再同时发网页心跳。
    @discardableResult
    static func reportAppWatch(bvid: String, aid: Int, cid: Int, report: PlaybackWatchReport,
                               expectedSessionID: UUID, client: APIClient = .shared,
                               identity: DeviceIdentity = .shared) async throws -> Int? {
        guard aid > 0, cid > 0, report.watchedTime.isFinite,
              (report.delivery == .start ? report.watchedTime == 0 : report.watchedTime > 0),
              report.position.isFinite,
              report.position == -1 || (report.position >= 0 && report.position < Double(Int.max)) else { return nil }
        let account = try await client.appAccount(expectedSessionID: expectedSessionID)
        guard account.mid != nil else { return nil }
        guard account.accessKey?.isEmpty == false else {
            guard report.delivery != .start else { return nil }
            // Cookie-only 登录仍保留旧的历史同步通道。
            try await reportWatchProgress(bvid: bvid, cid: cid, playedTime: report.position,
                                          expectedSessionID: expectedSessionID, client: client, identity: identity)
            return nil
        }
        let headers = try await identity.appRequestHeaders(expectedSessionID: expectedSessionID)
        var form = report.mobileParameters
        form["aid"] = String(aid); form["cid"] = String(cid)
        if let mid = account.mid { form["mid"] = String(mid) }
        let playbackSession = report.playbackSession.isEmpty
            ? UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() : report.playbackSession
        form["session"] = playbackSession
        form["sessionID"] = playbackSession
        var firstError: Error?
        var serverTimestamp: Int?
        if report.delivery != .checkpoint {
            do {
                let response: AppWatchAcknowledgement = try await client.postAppData(path: "x/report/heartbeat/mobile", form: form,
                    expectedSessionID: expectedSessionID, usesAPIHost: true, headers: headers)
                serverTimestamp = response.ts.flatMap { $0 > 0 ? $0 : nil }
            } catch { firstError = error }
        }
        // Zero start is mobile-only; it must not reset an existing history position.
        guard report.delivery != .start else {
            if let firstError { throw firstError }
            return serverTimestamp
        }
        // 心跳失败也仍尝试写历史；写操作不自动重试，超时不代表服务端未接收。
        let history = AppWatchProtocol.historyParameters(aid: aid, cid: cid, report: report,
            deviceTimestamp: Int(Date().timeIntervalSince1970))
        do {
            try await client.postApp(path: "x/v2/history/report", form: history,
                expectedSessionID: expectedSessionID, usesAPIHost: true, headers: headers)
        } catch { if firstError == nil { firstError = error } }
        if let firstError { throw firstError }
        return serverTimestamp
    }
}

struct AppWatchAcknowledgement: Decodable { let ts: Int? }
