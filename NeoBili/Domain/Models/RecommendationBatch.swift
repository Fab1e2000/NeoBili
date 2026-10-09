import Foundation

/// 每轮推荐固定来源。网页使用页码，App 使用服务端游标；pageIndex 也供录制回放定位批次。
struct RecommendationRequest: Equatable, Sendable {
    enum Source: Sendable { case app, web }
    let source: Source
    var pageIndex = 0
    var appCursor = 0
    /// 首批加载与刷新分开；翻页仍由 pageIndex 和服务端游标决定。
    var isRefresh = false
    /// Only used by an actual layout-triggered request; NeoBili currently keeps a fixed two-column layout.
    var isLayoutChange = false

    func next(appCursor: Int = 0) -> Self {
        Self(source: source, pageIndex: pageIndex == Int.max ? 1 : pageIndex + 1, appCursor: appCursor)
    }
}

struct RecommendationBatch {
    let videos: [VideoSummary]
    /// 缺失、重复游标或空页停止翻页，用户仍可刷新。不能回退到本地页码充当 App 游标。
    let nextRequest: RecommendationRequest?
    let refreshConfig: AppRecommendationRefreshConfig?
    let appCursor: Int?
    let refreshCursor: Int?
    let exposurePolicy: RecommendationExposurePolicy?

    init(videos: [VideoSummary], nextRequest: RecommendationRequest?,
         refreshConfig: AppRecommendationRefreshConfig? = nil, appCursor: Int? = nil,
         refreshCursor: Int? = nil,
         exposurePolicy: RecommendationExposurePolicy? = nil) {
        self.videos = videos
        self.nextRequest = nextRequest
        self.refreshConfig = refreshConfig
        self.appCursor = appCursor ?? nextRequest?.appCursor
        self.refreshCursor = refreshCursor
        self.exposurePolicy = exposurePolicy
    }
}
