import Foundation

extension ApplicationServices {
    static let live = Self(
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
