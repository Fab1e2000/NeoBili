import Foundation

struct AppRelatedPage {
    let videos: [VideoSummary]
    let pagination: Data?
    let canLoadMore: Bool
    /// Some server device cohorts omit this module from View and require RelatesFeed.
    let hasRelatedModule: Bool

}
