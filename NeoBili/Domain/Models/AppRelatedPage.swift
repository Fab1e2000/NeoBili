import Foundation

public struct AppRelatedPage {
    public let videos: [VideoSummary]
    public let pagination: Data?
    public let canLoadMore: Bool
    /// Some server device cohorts omit this module from View and require RelatesFeed.
    public let hasRelatedModule: Bool

    public init(
        videos: [VideoSummary],
        pagination: Data? = nil,
        canLoadMore: Bool,
        hasRelatedModule: Bool
    ) {
        self.videos = videos
        self.pagination = pagination
        self.canLoadMore = canLoadMore
        self.hasRelatedModule = hasRelatedModule
    }
}
