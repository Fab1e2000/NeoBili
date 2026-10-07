import Foundation

/// MainConfig values used by the official feed's independent show/duration checks.
/// A zero show threshold still requires a nonempty visible intersection.
struct RecommendationExposurePolicy: Decodable, Equatable, Sendable {
    var durationStartRatio: Double = 0.8
    var durationEndRatio: Double = 0.8
    var minimumDurationMilliseconds: Int = 0
    var showRatio: Double = 0

    init(durationStartRatio: Double = 0.8, durationEndRatio: Double = 0.8,
         minimumDurationMilliseconds: Int = 0, showRatio: Double = 0) {
        self.durationStartRatio = durationStartRatio
        self.durationEndRatio = durationEndRatio
        self.minimumDurationMilliseconds = max(0, minimumDurationMilliseconds)
        self.showRatio = showRatio
    }

    private enum CodingKeys: String, CodingKey {
        case durationStartRatio = "exposure_duration_start_ratio"
        case durationEndRatio = "exposure_duration_end_ratio"
        case minimumDurationMilliseconds = "exposure_duration_min_ms"
        case visibleArea = "visible_area"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func number(_ key: CodingKeys, fallback: Double) -> Double {
            guard let value = try? values.decode(Double.self, forKey: key), value.isFinite else { return fallback }
            return value
        }
        durationStartRatio = number(.durationStartRatio, fallback: 0.8)
        durationEndRatio = number(.durationEndRatio, fallback: 0.8)
        minimumDurationMilliseconds = max(0, (try? values.decode(Int.self, forKey: .minimumDurationMilliseconds)) ?? 0)
        showRatio = number(.visibleArea, fallback: 0) / 100
    }
}
