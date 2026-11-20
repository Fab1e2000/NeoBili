import Foundation

/// Keep row identity stable across overlapping pages and repeated records within one response.
enum LibraryPageRules {
    static func unique<Item: Identifiable>(_ incoming: [Item], excluding existing: Set<Item.ID> = []) -> [Item] {
        var seen = existing
        return incoming.filter { seen.insert($0.id).inserted }
    }

    /// History can include non-video records: only the server cursor determines continuation.
    static func advancesHistory(max: Int?, viewAt: Int?, fromMax: Int, fromViewAt: Int) -> Bool {
        guard let max, max > 0 else { return false }
        return max != fromMax || (viewAt ?? 0) != fromViewAt
    }

    static func hasMoreFavorites(rawCount: Int, pageSize: Int = 20) -> Bool {
        rawCount >= pageSize
    }
}
