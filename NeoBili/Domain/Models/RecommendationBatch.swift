import Foundation

/// 每轮推荐固定来源。网页使用页码，App 使用服务端游标；pageIndex 也供录制回放定位批次。
public struct RecommendationRequest: Equatable, Sendable {
    public enum Source: Sendable { case app, web }
    public let source: Source
    public var pageIndex = 0
    public var appCursor = 0
    /// 首批加载与刷新分开；翻页仍由 pageIndex 和服务端游标决定。
    public var isRefresh = false
    /// Only used by an actual layout-triggered request; NeoBili currently keeps a fixed two-column layout.
    public var isLayoutChange = false

    public func next(appCursor: Int = 0) -> Self {
        Self(source: source, pageIndex: pageIndex == Int.max ? 1 : pageIndex + 1, appCursor: appCursor)
    }

    public init(
        source: Source,
        pageIndex: Int = 0,
        appCursor: Int = 0,
        isRefresh: Bool = false,
        isLayoutChange: Bool = false
    ) {
        self.source = source
        self.pageIndex = pageIndex
        self.appCursor = appCursor
        self.isRefresh = isRefresh
        self.isLayoutChange = isLayoutChange
    }
}

public struct RecommendationBatch {
    public let videos: [VideoSummary]
    /// 缺失、重复游标或空页停止翻页，用户仍可刷新。不能回退到本地页码充当 App 游标。
    public let nextRequest: RecommendationRequest?
    public let refreshConfig: AppRecommendationRefreshConfig?
    public let appCursor: Int?
    public let refreshCursor: Int?
    public let exposurePolicy: RecommendationExposurePolicy?

    public init(videos: [VideoSummary], nextRequest: RecommendationRequest?,
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
