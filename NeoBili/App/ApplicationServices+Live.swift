import Foundation

extension ApplicationServices {
    static let live = Self(
        currentAppBuvid: { await DeviceIdentity.shared.appBuvid() },
        exportDiagnostics: { try await RecommendationDiagnostics.shared.export() },
        telemetry: .live,
        authentication: .live,
        session: .live(),
        links: .live,
        search: .live(),
        library: .live(),
        video: .live(),
        account: .live(),
        comment: .live(),
        streaming: .live(),
        community: .live(),
        recommendation: .live()
    )
}

extension HomeFeedAccount {
    static func current() async -> Self { await ApplicationServices.live.session.homeAccount() }
}

extension ApplicationServices {
    @MainActor static func makeLiveDanmakuStream() -> any LiveDanmakuStreaming { LiveDanmakuConnection() }
}

extension ApplicationServices {
    @MainActor static func recordExposure(_ event: RecommendationExposureEvent) { LiveExposureReporting.record(event) }
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
