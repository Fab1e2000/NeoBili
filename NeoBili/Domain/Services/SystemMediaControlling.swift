import Foundation

public struct SystemMediaMetadata: Equatable, Sendable {
    public let identifier: String
    public let title: String
    public let artist: String
    public let artworkURL: URL?
    public var isLiveStream: Bool = false

    public init(
        identifier: String,
        title: String,
        artist: String,
        artworkURL: URL? = nil,
        isLiveStream: Bool = false
    ) {
        self.identifier = identifier
        self.title = title
        self.artist = artist
        self.artworkURL = artworkURL
        self.isLiveStream = isLiveStream
    }
}

/// Playback coordination depends on operations, not system media framework objects.
@MainActor
public protocol SystemMediaControlling: AnyObject {
    func activate(sessionID: UUID, metadata: SystemMediaMetadata,
                  onPlay: @escaping () -> Void, onPause: @escaping () -> Void,
                  onToggle: @escaping () -> Void, onSeek: @escaping (TimeInterval) -> Void)
    func deactivate(sessionID: UUID)
    func updateDuration(_ value: TimeInterval, sessionID: UUID)
    func updateElapsed(_ value: TimeInterval, sessionID: UUID, force: Bool)
    func updatePlaybackState(isPlaying: Bool, sessionID: UUID, rate: Double)
}

extension SystemMediaControlling {
    public func updateElapsed(_ value: TimeInterval, sessionID: UUID) {
        updateElapsed(value, sessionID: sessionID, force: false)
    }
    public func updatePlaybackState(isPlaying: Bool, sessionID: UUID) {
        updatePlaybackState(isPlaying: isPlaying, sessionID: sessionID, rate: 1)
    }
}
