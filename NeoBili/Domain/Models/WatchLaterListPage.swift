import Foundation

public struct WatchLaterListPage: Sendable {
        public var items: [WatchLaterItem]
        public var nextKey: String = ""
        public var splitKey: String = ""
        public var hasMore = false

        public init(
            items: [WatchLaterItem],
            nextKey: String = "",
            splitKey: String = "",
            hasMore: Bool = false
        ) {
            self.items = items
            self.nextKey = nextKey
            self.splitKey = splitKey
            self.hasMore = hasMore
        }
    }
