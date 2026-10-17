import Foundation

/// 离线测试桩：PortraitVideoStore 默认 loader 引用的播放预取缓存在 App 里
/// 依赖 mpv/SwiftUI。宿主机上它只需返回确定性的详情数据，让 shared store
/// 的补查路径可以在测试里真实走通。
actor VideoPreparationCache {
    static let shared = VideoPreparationCache()

    func detail(for bvid: String) async throws -> VideoDetail {
        VideoDetail(
            bvid: bvid,
            aid: 1,
            cid: 1,
            title: bvid,
            desc: "",
            pic: "",
            duration: 700,
            pubdate: 0,
            owner: VideoOwner(mid: 1, name: "UP", face: ""),
            stat: VideoStat(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0),
            pages: [],
            dimension: VideoDimension(width: 1920, height: 1080),
            tname: nil,
            copyright: nil,
            ugcSeason: nil
        )
    }
}

/// AccountStore（依赖 SwiftUI/Network）里的凭据快照，测试只需要这个形状。
struct AccountCredentialsSnapshot: Sendable {
    let hasCredentials: Bool
    var hasAppCredential = false
    var needsAppReauthorization = false
    var needsAppCredentialMigration = false
    let accountID: Int?
}

// Host composition root: the same service contracts and adapters as the app.
// Only presentation-only services are omitted from this smaller executable.
struct ApplicationServices {
    var session: SessionService = .live(identity: .shared)
    var video: VideoService = .live(client: .shared, identity: .shared)
    var recommendation: RecommendationService = .live(client: .shared, identity: .shared, session: .shared,
        network: .shared, clickReporter: .shared, filter: { .current() })
    static let live = ApplicationServices()
}
extension HomeFeedAccount {
    static func current() async -> Self { await ApplicationServices.live.session.homeAccount() }
}
public enum ServiceError: Error { case unconfigured(String) }

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
    static let defaults = UserDefaults(suiteName: "neobili.offline.networking.\(UUID().uuidString)")!
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
