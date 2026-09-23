import Foundation

extension BiliAPI {
    /// 使用 PiliPlus 的 App 推荐接口，列表刷新与分页仍由原 ViewModel 管理。
    static func recommendFeed(freshIndex: Int) async throws -> [VideoSummary] {
        let page: AppRecommendationPage = try await APIClient.shared.getApp(
            path: "x/v2/feed/index", params: AppRecommendationPage.parameters(freshIndex: freshIndex)
        )
        return page.videos
    }

    /// 首页推荐的内容反馈，与视频页的点踩分别上报。
    static func markRecommendationUninterested(_ video: VideoSummary) async throws {
        var form = recommendationFeedbackForm(video)
        form["csrf"] = await DeviceIdentity.shared.csrfToken ?? ""
        try await APIClient.shared.post(path: "x/web-interface/feedback/dislike", form: form)
    }

    static func recommendationFeedbackForm(_ video: VideoSummary) -> [String: String] {
        ["app_id": "100", "platform": "5", "from_spmid": "", "spmid": "333.1007.0.0",
         "goto": "av", "id": String(video.aid), "mid": String(video.owner.mid),
         "track_id": video.recommendationTrackID ?? "", "feedback_page": "1", "reason_id": "1"]
    }
}
