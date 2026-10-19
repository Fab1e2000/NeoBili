import Foundation

/// 每轮推荐固定来源。网页使用页码，App 使用服务端游标；pageIndex 也供录制回放定位批次。
public struct RecommendationRequest: Equatable, Sendable {
    public enum Source: String, CaseIterable, Sendable { case app, web, merged }
    public static let sourceKey = "neobili.rcmd.source"
    public static func savedSource(rawValue: String?, legacyUsesApp: Bool?) -> Source {
        rawValue.flatMap(Source.init(rawValue:)) ?? (legacyUsesApp == false ? .web : .app)
    }
    public let source: Source
    public var pageIndex = 0
    public var appCursor = 0
    public var appPageIndex = 0
    public var appFinished = false
    public var webFinished = false
    public var webPageIndex = 0
    /// 首批加载与刷新分开；翻页仍由 pageIndex 和服务端游标决定。
    public var isRefresh = false
    /// Only used by an actual layout-triggered request; NeoBili currently keeps a fixed two-column layout.
    public var isLayoutChange = false

    public func next(appCursor: Int = 0) -> Self {
        var next = self
        next.pageIndex = pageIndex == Int.max ? 1 : pageIndex + 1
        next.appCursor = appCursor
        next.isRefresh = false
        next.isLayoutChange = false
        return next
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

public struct RecommendationBatch: Sendable {
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
