import Foundation

public struct AppRecommendationRefreshConfig: Decodable, Equatable, Sendable {
    public enum Trigger { case active, appear, behavior }
    public let active: TimeInterval?
    public let appear: TimeInterval?
    public let behavior: TimeInterval?

    private enum Keys: String, CodingKey {
        case legacy = "auto_refresh_time"
        case active = "auto_refresh_time_by_active"
        case appear = "auto_refresh_time_by_appear"
        case behavior = "auto_refresh_time_by_behavior"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        func interval(_ key: Keys) -> TimeInterval? {
            let value = (try? c.decode(Int.self, forKey: c.contains(key) ? key : .legacy)) ?? (try? c.decode(String.self, forKey: c.contains(key) ? key : .legacy)).flatMap(Int.init)
            return value.flatMap { $0 > 0 ? TimeInterval($0) : nil }
        }
        active = interval(.active)
        appear = interval(.appear)
        behavior = interval(.behavior)
    }

    public func interval(for trigger: Trigger) -> TimeInterval? {
        switch trigger {
        case .active: active
        case .appear: appear
        case .behavior: behavior
        }
    }
}
