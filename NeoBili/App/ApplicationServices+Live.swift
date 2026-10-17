import Foundation
import AVFAudio

extension ApplicationServices {
    static let live = makeLive(identity: .shared, client: .shared, session: AppNetwork.session,
                              diagnostics: .shared, network: .shared, recommendationSession: .shared,
                              reporter: .shared, clickReporter: .shared)

    static func makeLive(identity: DeviceIdentity, client: APIClient, session: URLSession,
                         diagnostics: RecommendationDiagnostics, network: AppNetworkMetadata,
                         recommendationSession: AppRecommendationSession, reporter: AppBehaviorReporter,
                         clickReporter: RecommendationClickReporter,
                         filter: @escaping @Sendable () -> RecommendationFilter = { .current() }) -> Self {
        Self(
            currentAppBuvid: { await identity.appBuvid() },
            exportDiagnostics: { try await diagnostics.export() },
            telemetry: .live(identity: identity, reporter: reporter, clickReporter: clickReporter),
            authentication: .live(session: session, identity: identity),
            session: .live(identity: identity),
            links: .live(session: session),
            search: .live(client: client),
            library: .live(client: client, identity: identity),
            video: .live(client: client, identity: identity),
            account: .live(client: client),
            comment: .live(client: client, identity: identity),
            streaming: .live(client: client, identity: identity, session: session),
            community: .live(client: client, identity: identity),
            recommendation: .live(client: client, identity: identity, session: recommendationSession,
                                  network: network, clickReporter: clickReporter, filter: filter)
        )
    }
}

extension HomeFeedAccount {
    static func current() async -> Self { await ApplicationServices.live.session.homeAccount() }
}

extension ApplicationServices {
    @MainActor static func makeLiveDanmakuStream() -> any LiveDanmakuStreaming { LiveDanmakuConnection() }
}

extension ApplicationServices {
    @MainActor static func recordExposure(_ event: RecommendationExposureEvent) { LiveExposureReporting.record(event, currentSessionID: live.session.currentID(), reporter: .shared) }
    static func loadDanmaku(cid: Int) async throws -> [DanmakuItem] { try await DanmakuLoader.load(cid: cid) }
}

extension ApplicationServices {
    static func imageData(_ url: URL) async throws -> Data { try await BiliImageDataLoader.data(for: url) }
}


extension PlaybackDependencies {
    @MainActor static let live = Self(
        services: .live,
        preparation: ApplicationServices.playbackPreparation,
        progress: PlaybackProgressStore(),
        likes: .shared,
        systemMedia: SystemNowPlayingCenter.shared
    )
}

extension ApplicationServices {
    static let playbackPreparation = VideoPreparationCache(
            detailLoader: { try await ApplicationServices.live.video.videoDetail(bvid: $0) },
            playbackLoader: { try await ApplicationServices.live.video.playURL(bvid: $0, cid: $1) },
            sessionProvider: { ApplicationServices.live.session.currentID() }
        )
}

// Compatibility entry points resolve to the same production graph.
extension PlaybackProgressStore {
    static var shared: PlaybackProgressStore { PlaybackDependencies.live.progress }
}
extension VideoPreparationCache {
    static var shared: VideoPreparationCache { ApplicationServices.playbackPreparation }
}

extension SystemNowPlayingCenter {
    @MainActor static let shared = SystemNowPlayingCenter(
        output: .system(), notifications: .default,
        interruptionObject: AVAudioSession.sharedInstance(), idleTimer: PlaybackIdleTimer(),
        artworkLoader: { url in
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.setValue(BiliHeaders.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(BiliHeaders.referer, forHTTPHeaderField: "Referer")
            return try await AppNetwork.session.data(for: request).0
        }
    )
}

extension PlaybackWatchProgressSender {
    static func shared(loginSessionID: UUID, bvid: String, cid: Int,
                       report: @escaping @Sendable (Double) async -> Void) -> PlaybackWatchProgressSender {
        PlaybackDependencies.live.watchProgress.sender(loginSessionID: loginSessionID, bvid: bvid, cid: cid, report: report)
    }
}
extension PlaybackWatchReportSender {
    static func shared(loginSessionID: UUID, bvid: String, cid: Int,
                       report: @escaping @Sendable (PlaybackWatchReport) async -> Void) -> PlaybackWatchReportSender {
        PlaybackDependencies.live.watchReports.sender(loginSessionID: loginSessionID, bvid: bvid, cid: cid, report: report)
    }
    static func shared(loginSessionID: UUID, bvid: String, cid: Int,
                       serverReport: @escaping @Sendable (PlaybackWatchReport) async -> Int?) -> PlaybackWatchReportSender {
        PlaybackDependencies.live.watchReports.sender(loginSessionID: loginSessionID, bvid: bvid, cid: cid, serverReport: serverReport)
    }
}

extension ApplicationStores {
    @MainActor static let live = Self(likes: VideoLikeStore(), followingRead: FollowingReadStore(), searchHistory: SearchHistory())
}
extension VideoLikeStore {
    static var shared: VideoLikeStore { ApplicationStores.live.likes }
}
extension FollowingReadStore {
    static var shared: FollowingReadStore { ApplicationStores.live.followingRead }
}
extension SearchHistory {
    static var shared: SearchHistory { ApplicationStores.live.searchHistory }
}

extension VideoFilterDependencies {
    @MainActor static let live = Self(duration: VideoDurationFilterSettings(), metadata: PortraitVideoStore(metadataLoader: loadMetadata))

    private static func loadMetadata(_ bvid: String) async throws -> PortraitVideoStore.Metadata {
        let detail = try await ApplicationServices.playbackPreparation.detail(for: bvid)
        return .init(dimension: detail.dimension, durationSeconds: detail.duration)
    }
}
extension VideoDurationFilterSettings {
    static var shared: VideoDurationFilterSettings { VideoFilterDependencies.live.duration }
}
extension PortraitVideoStore {
    static var shared: PortraitVideoStore { VideoFilterDependencies.live.metadata }
}

extension OwnerAvatarCache {
    static let shared = OwnerAvatarCache(loader: { mid in
        try await ApplicationServices.live.community.spaceCard(mid: mid).secureAvatarURL
    })
}
extension PlaybackAudioSession {
    @MainActor static let shared = PlaybackAudioSession(endpoint: .live)
}
extension PlayerChromePreferences {
    @MainActor static let shared = PlayerChromePreferences()
}
