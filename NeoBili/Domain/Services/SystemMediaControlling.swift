import Foundation

struct SystemMediaMetadata: Equatable, Sendable {
    let identifier: String
    let title: String
    let artist: String
    let artworkURL: URL?
    var isLiveStream: Bool = false
}

/// Playback coordination depends on operations, not system media framework objects.
@MainActor
protocol SystemMediaControlling: AnyObject {
    func activate(sessionID: UUID, metadata: SystemMediaMetadata,
                  onPlay: @escaping () -> Void, onPause: @escaping () -> Void,
                  onToggle: @escaping () -> Void, onSeek: @escaping (TimeInterval) -> Void)
    func deactivate(sessionID: UUID)
    func updateDuration(_ value: TimeInterval, sessionID: UUID)
    func updateElapsed(_ value: TimeInterval, sessionID: UUID, force: Bool)
    func updatePlaybackState(isPlaying: Bool, sessionID: UUID, rate: Double)
}

extension SystemMediaControlling {
    func updateElapsed(_ value: TimeInterval, sessionID: UUID) {
        updateElapsed(value, sessionID: sessionID, force: false)
    }
    func updatePlaybackState(isPlaying: Bool, sessionID: UUID) {
        updatePlaybackState(isPlaying: isPlaying, sessionID: sessionID, rate: 1)
    }
}
