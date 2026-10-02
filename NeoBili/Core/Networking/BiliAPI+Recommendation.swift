import Foundation

/// 每轮推荐固定来源。网页使用页码，App 使用服务端游标；pageIndex 也供录制回放定位批次。
struct RecommendationRequest: Equatable, Sendable {
    enum Source: Sendable { case app, web }
    let source: Source
    var pageIndex = 0
    var appCursor = 0

    func next(appCursor: Int = 0) -> Self {
        Self(source: source, pageIndex: pageIndex == Int.max ? 1 : pageIndex + 1, appCursor: appCursor)
    }
}

struct RecommendationBatch {
    let videos: [VideoSummary]
    /// 缺失、重复游标或空页停止翻页，用户仍可刷新。不能回退到本地页码充当 App 游标。
    let nextRequest: RecommendationRequest?
    let refreshConfig: AppRecommendationRefreshConfig?

    init(videos: [VideoSummary], nextRequest: RecommendationRequest?,
         refreshConfig: AppRecommendationRefreshConfig? = nil) {
        self.videos = videos
        self.nextRequest = nextRequest
        self.refreshConfig = refreshConfig
    }
}

extension BiliAPI {
    static func recommendFeed(request: RecommendationRequest) async throws -> RecommendationBatch {
        switch request.source {
        case .app:
            return try await appRecommendFeed(request: request)
        case .web:
            let videos = try await webRecommendFeed(freshIndex: request.pageIndex)
            return RecommendationBatch(videos: videos, nextRequest: videos.isEmpty ? nil : request.next())
        }
    }

    /// 网页推荐：Cookie 认证 + WBI 签名，每次 20 条。
    static func webRecommendFeed(freshIndex: Int) async throws -> [VideoSummary] {
        let page: WebRecommendationPage = try await APIClient.shared.get(
            path: "x/web-interface/wbi/index/top/feed/rcmd",
            params: WebRecommendationPage.parameters(freshIndex: freshIndex), requiresWBI: true
        )
        return page.videos(filter: .current())
    }

    static func appRecommendFeed(request: RecommendationRequest) async throws -> RecommendationBatch {
        let page: AppRecommendationPage = try await APIClient.shared.getApp(
            path: "x/v2/feed/index",
            params: AppRecommendationPage.parameters(cursor: request.appCursor, pull: request.pageIndex == 0),
            headers: AppRecommendationPage.headers(buvid: await DeviceIdentity.shared.appBuvid())
        )
        return page.batch(for: request, filter: .current())
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
        AppClientIdentity.parameters.merging(["goto": options.goto, "id": String(options.param)]) { _, value in value }
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
