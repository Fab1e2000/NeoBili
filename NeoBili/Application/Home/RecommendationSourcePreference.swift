import Foundation
#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif

/// Frozen at process launch; saving a preference never changes an active feed.
enum RecommendationSourcePreference {
    static let launched = saved()
    static func saved(defaults: UserDefaults = .standard) -> RecommendationRequest.Source {
        RecommendationRequest.savedSource(rawValue: defaults.string(forKey: RecommendationRequest.sourceKey),
            legacyUsesApp: defaults.object(forKey: RecommendationFilter.appRecommendKey) as? Bool)
    }
}
