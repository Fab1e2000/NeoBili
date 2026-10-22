#if canImport(NeoBiliDomain)
@testable import NeoBiliDomain
#endif
import Foundation
@testable import NeoBili

@MainActor
extension PlaybackDependencies {
    static func isolated(defaults: UserDefaults) -> Self {
        let sessionID = UUID()
        let services = ApplicationServices(session: .init(currentID: { sessionID },
            homeAccount: { .init(accountID: nil, hasAppCredential: false) }))
        return Self(services: services,
            preparation: VideoPreparationCache(
                detailLoader: { _ in throw URLError(.notConnectedToInternet) },
                playbackLoader: { _, _ in throw URLError(.notConnectedToInternet) },
                scrollPrefetchEnabled: { false }, sessionProvider: { sessionID }),
            progress: PlaybackProgressStore(defaults: defaults), likes: VideoLikeStore(),
            systemMedia: SilentSystemMedia())
    }
}

@MainActor
private final class SilentSystemMedia: SystemMediaControlling {
    func activate(sessionID: UUID, metadata: SystemMediaMetadata,
                  onPlay: @escaping () -> Void, onPause: @escaping () -> Void,
                  onToggle: @escaping () -> Void, onSeek: @escaping (TimeInterval) -> Void) {}
    func deactivate(sessionID: UUID) {}
    func updateDuration(_ value: TimeInterval, sessionID: UUID) {}
    func updateElapsed(_ value: TimeInterval, sessionID: UUID, force: Bool) {}
    func updatePlaybackState(isPlaying: Bool, sessionID: UUID, rate: Double) {}
}
