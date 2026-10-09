import Foundation
import Synchronization

/// Reuse the expensive localized formatter setup across list rows. Locale and
/// time zone are part of the key, so a settings/time-zone change cannot reuse a
/// formatter configured for the previous environment. Formatting is serialized
/// with cache access; callers never receive a mutable shared DateFormatter.
enum BiliDateFormatting {
    private struct Key: Hashable {
        let template: String
        let locale: Locale
        let timeZone: TimeZone
        let calendar: Calendar
    }
    private static let formatters = Mutex<[Key: DateFormatter]>([:])

    static func string(
        from date: Date,
        template: String,
        locale: Locale,
        timeZone: TimeZone = .current
    ) -> String {
        let key = Key(template: template, locale: locale, timeZone: timeZone, calendar: .current)
        return formatters.withLock { cache in
            if let formatter = cache[key] { return formatter.string(from: date) }
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.setLocalizedDateFormatFromTemplate(template)
            // Only three templates are used in production. Bound unusual locale
            // and zone combinations without adding a periodic invalidation task.
            if cache.count >= 16 { cache.removeAll(keepingCapacity: true) }
            cache[key] = formatter
            return formatter.string(from: date)
        }
    }
}
