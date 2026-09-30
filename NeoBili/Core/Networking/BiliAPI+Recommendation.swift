import Foundation

extension BiliAPI {
    /// 首页推荐：和 PiliPlus 一样默认用 App 推荐，设置里可换成网页推荐；
    /// 两者都在请求后按推荐流设置做本地过滤。
    static func recommendFeed(freshIndex: Int) async throws -> [VideoSummary] {
        let usesApp = UserDefaults.standard.object(forKey: RecommendationFilter.appRecommendKey) as? Bool ?? true
        return usesApp ? try await appRecommendFeed(freshIndex: freshIndex)
                       : try await webRecommendFeed(freshIndex: freshIndex)
    }

    /// 网页推荐：Cookie 认证 + WBI 签名，每次 20 条。
    static func webRecommendFeed(freshIndex: Int) async throws -> [VideoSummary] {
        let page: WebRecommendationPage = try await APIClient.shared.get(
            path: "x/web-interface/wbi/index/top/feed/rcmd",
            params: WebRecommendationPage.parameters(freshIndex: freshIndex), requiresWBI: true
        )
        return page.videos(filter: .current())
    }

    static func appRecommendFeed(freshIndex: Int) async throws -> [VideoSummary] {
        let page: AppRecommendationPage = try await APIClient.shared.getApp(
            path: "x/v2/feed/index", params: AppRecommendationPage.parameters(freshIndex: freshIndex),
            headers: AppRecommendationPage.headers(buvid: await DeviceIdentity.shared.appBuvid())
        )
        return page.videos(filter: .current())
    }

    /// 「不感兴趣」：`reason` 是用户在卡片原因里选的一项，「我不想看」或「反馈」。
    static func feedDislike(_ options: RecommendationFeedbackOptions,
                            reason: RecommendationFeedbackOptions.Reason,
                            expectedSessionID: UUID? = nil,
                            client: APIClient = .shared) async throws {
        var params = feedbackParameters(options)
        if options.dislikeReasons?.contains(reason) == true {
            params["reason_id"] = String(reason.id)
        } else {
            params["feedback_id"] = String(reason.id)
        }
        try await sendFeedback(path: "x/feed/dislike", params: params,
                               expectedSessionID: expectedSessionID, client: client)
    }

    /// 撤销这张卡片的「不感兴趣」。
    static func feedDislikeCancel(_ options: RecommendationFeedbackOptions,
                                 expectedSessionID: UUID? = nil,
                                 client: APIClient = .shared) async throws {
        try await sendFeedback(path: "x/feed/dislike/cancel", params: feedbackParameters(options),
                               expectedSessionID: expectedSessionID, client: client)
    }

    static func feedbackParameters(_ options: RecommendationFeedbackOptions) -> [String: String] {
        ["goto": options.goto, "id": String(options.param), "build": "1", "mobi_app": "android"]
    }

    private static func sendFeedback(path: String, params: [String: String],
                                     expectedSessionID: UUID?, client: APIClient) async throws {
        let account = try await client.appAccount(expectedSessionID: expectedSessionID)
        guard account.accessKey != nil else {
            throw account.mid != nil
                ? RecommendationFeedbackError.missingAccessKey : RecommendationFeedbackError.notLoggedIn
        }
        // 这是使用 GET 的写操作。超时不代表服务端没收到，自动重试会重复上报。
        let _: IgnoredData = try await client.getApp(
            path: path, params: params, retries: 0, expectedSessionID: expectedSessionID ?? account.sessionID
        )
    }
}

/// 反馈接口只看 code，data 是什么都不关心。
private struct IgnoredData: Decodable {
    init(from decoder: Decoder) throws {}
}

enum RecommendationFeedbackError: LocalizedError {
    case notLoggedIn
    case missingAccessKey

    var errorDescription: String? {
        switch self {
        case .notLoggedIn: String(localized: "账号未登录")
        case .missingAccessKey: String(localized: "请退出账号后重新登录")
        }
    }
}
