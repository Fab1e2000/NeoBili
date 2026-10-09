import Foundation

struct WatchLaterListPage: Sendable {
        var items: [WatchLaterItem]
        var nextKey: String = ""
        var splitKey: String = ""
        var hasMore = false
    }
