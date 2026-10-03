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
    var mobileParameters: [String: String] {
        func seconds(_ value: Double) -> String {
            String(Int(max(0, min(Double(Int.max) / 2, value.isFinite ? value : 0)).rounded(.down)))
        }
        var fields = AppClientIdentity.parameters.merging(sourceFields) { _, value in value }
        fields.merge([
            "actionKey": "appkey", "statistics": AppClientIdentity.statistics,
            "type": "3", "sub_type": "0", "auto_play": "0", "play_type": "1",
            "c_locale": "zh-Hans_CN", "s_locale": "zh-Hans_CN",
            "played_time": seconds(watchedTime), "actual_played_time": seconds(watchedTime),
            "paused_time": seconds(pausedTime), "miniplayer_play_time": seconds(miniPlayerTime), "total_time": seconds(watchedTime + pausedTime),
            "last_play_progress_time": seconds(position == -1 ? maximumPosition : position),
            "max_play_progress_time": seconds(maximumPosition), "video_duration": seconds(duration),
            "start_ts": String(startTimestamp)
        ]) { _, value in value }
        return fields
    }
}

extension BiliAPI {
    /// App 授权存在时使用移动心跳与独立历史同步，不再同时发网页心跳。
    static func reportAppWatch(bvid: String, aid: Int, cid: Int, report: PlaybackWatchReport,
                               expectedSessionID: UUID, client: APIClient = .shared,
                               identity: DeviceIdentity = .shared) async throws {
        guard aid > 0, cid > 0, report.watchedTime.isFinite, report.watchedTime > 0,
              report.position.isFinite,
              report.position == -1 || (report.position >= 1 && report.position < Double(Int.max)) else { return }
        let account = try await client.appAccount(expectedSessionID: expectedSessionID)
        guard account.mid != nil else { return }
        guard account.accessKey?.isEmpty == false else {
            // Cookie-only 登录仍保留旧的历史同步通道。
            try await reportWatchProgress(bvid: bvid, cid: cid, playedTime: report.position,
                                          expectedSessionID: expectedSessionID, client: client, identity: identity)
            return
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
        do {
            try await client.postApp(path: "x/report/heartbeat/mobile", form: form,
                expectedSessionID: expectedSessionID, usesAPIHost: true, headers: headers)
        } catch { firstError = error }
        // 心跳失败也仍尝试写历史；写操作不自动重试，超时不代表服务端未接收。
        var history = AppClientIdentity.parameters
        history.merge(["aid": String(aid), "cid": String(cid), "type": "3", "sub_type": "0",
                       "progress": String(Int(report.position.rounded(.down))),
                       "start_ts": String(report.startTimestamp), "statistics": AppClientIdentity.statistics,
                       "actionKey": "appkey", "c_locale": "zh-Hans_CN", "s_locale": "zh-Hans_CN",
                       "duration": String(Int(max(0, min(Double(Int.max) / 2, report.duration.isFinite ? report.duration : 0)).rounded(.down))),
                       "device_ts": String(Int(Date().timeIntervalSince1970)),
                       "disable_rcmd": "0", "teenagers_age": "16", "epid": "0", "sid": "0"]) { _, value in value }
        do {
            try await client.postApp(path: "x/v2/history/report", form: history,
                expectedSessionID: expectedSessionID, usesAPIHost: true, headers: headers)
        } catch { if firstError == nil { firstError = error } }
        if let firstError { throw firstError }
    }
}
