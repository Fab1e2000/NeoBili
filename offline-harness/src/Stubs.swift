import Foundation
import NeoBiliDomain
@testable import NeoBiliData

// The host uses real service contracts and adapters with isolated credentials.
extension ApplicationServices {
    static let live = ApplicationServices(
        session: .live(identity: .shared),
        video: .live(client: .shared, identity: .shared),
        recommendation: .live(client: .shared, identity: .shared, session: .shared,
            network: .shared, clickReporter: .shared, filter: { .current() })
    )
}

extension HomeFeedAccount {
    static func current() async -> Self { await ApplicationServices.live.session.homeAccount() }
}

extension VideoFilterDependencies {
    @MainActor static let live: Self = {
        let defaults = UserDefaults(suiteName: "neobili.offline.filters.\(UUID().uuidString)")!
        return Self(duration: VideoDurationFilterSettings(defaults: defaults),
                    metadata: PortraitVideoStore(defaults: defaults, metadataLoader: { _ in
                        .init(dimension: .init(width: 1920, height: 1080), durationSeconds: 700)
                    }))
    }()
}

private enum HostNetworking {
    static let suite = "neobili.offline.networking.\(UUID().uuidString)"
    static var defaults: UserDefaults { UserDefaults(suiteName: suite)! }
}
extension DeviceIdentity {
    static let shared = DeviceIdentity(defaults: HostNetworking.defaults, credentials: .memory(),
                                       allowsNetwork: false, purgeCookies: {})
}
extension AppNetworkMetadata {
    static let shared = AppNetworkMetadata(monitoring: false)
}
extension WBISigner {
    static let shared = WBISigner(defaults: HostNetworking.defaults)
}
extension RecommendationDiagnostics {
    static let shared = RecommendationDiagnostics(enabled: { false })
}
extension APIClient {
    static let shared = APIClient()
}
extension AppRecommendationSession {
    static let shared = AppRecommendationSession()
}
extension AppBehaviorReporter {
    static let shared = AppBehaviorReporter(identity: .shared, client: .shared, automaticScheduling: false)
}
extension RecommendationClickReporter {
    static let shared = RecommendationClickReporter(identity: .shared, client: .shared)
}

extension ApplicationServices {
    static var homeRecommendations: @Sendable (RecommendationRequest) async throws -> RecommendationBatch {
        live.recommendation.recommendFeed
    }
}

extension AppNetwork {
    static let session = makeSession()
}
