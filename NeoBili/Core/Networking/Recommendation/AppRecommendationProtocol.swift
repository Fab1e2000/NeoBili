import Foundation

/// Request policy is independent of response decoding and page presentation.
enum AppRecommendationProtocol {
    /// 游标和刷新标记属于分页协议；客户端参数与登录、反馈共用 iPhone 身份。
    static func parameters(for request: RecommendationRequest, display: AppRecommendationDisplay? = nil, openEvent: String = "", bannerHash: String = "", network: String = "") -> [String: String] {
        let pull = request.pageIndex == 0
        // 官方 iPhone 抓包：首次 0、刷新 6、翻页 8；pull 使用数字布尔值。
        // 固定项采用用户确认的策略；启动、横幅与游标按自身状态生成。
        var params = AppClientIdentity.parameters.merging([
            "actionKey": "appkey", "device_name": AppClientIdentity.deviceName, "c_locale": "zh-Hans_CN", "s_locale": "zh-Hans_CN", "column": "4",
            "disable_rcmd": "0", "flush": pull ? (request.isLayoutChange ? "2" : (request.isRefresh ? "6" : "0")) : "8",
            "fnval": "84948", "fnver": "0", "force_host": "0",
            "fourk": "1", "guidance": "1", "https_url_req": "0", "idx": String(request.appCursor),
            "pull": pull ? "1" : "0",
            "qn": "32", "recsys_mode": "0", "splash_id": "", "voice_balance": "0",
            "statistics": AppClientIdentity.statistics,
            "auto_refresh_state": "4", "login_event": "0", "open_event": openEvent,
            "inline_sound": "1", "inline_sound_cold_state": "4", "autoplay_card": "10",
            "video_mode": "1", "inline_danmu": "1", "client_attr": "0", "qn_policy": "1",
            "network": network, "player_net": network == "mobile" ? "2" : (network == "wifi" ? "1" : "3"), "soft_fnval": "2", "teenagers_age": "16",
            "banner_hash": bannerHash, "splash_ids": "", "splash_creative_id": ""
        ]) { _, value in value }
        if let display { params["player_extra_content"] = display.playerExtraContent }
        return params
    }

}
