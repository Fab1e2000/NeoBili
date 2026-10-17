import Foundation

public struct PlaybackTelemetryEvent: Sendable {
    public let name: String
    public let aid: Int
    public let cid: Int
    public let position: Double
    public let playbackSession: String
    public let source: [String: String]
    public let accountSession: UUID
    public let quality: Int?
    public let playbackRate: Double
    public let sequence: Int
    public let inlinePreview: Bool
}

public struct TelemetryService: Sendable {
    public var playback: @MainActor @Sendable (PlaybackTelemetryEvent) -> Void = { _ in }
    public var click: @MainActor @Sendable (VideoSummary) -> Void = { _ in }

    @MainActor public func record(_ name: String, aid: Int, cid: Int, position: Double, playbackSession: String,
                          source: [String: String], accountSession: UUID, quality: Int?,
                          playbackRate: Double = 1, sequence: Int, inlinePreview: Bool = false) {
        playback(.init(name: name, aid: aid, cid: cid, position: position, playbackSession: playbackSession,
                       source: source, accountSession: accountSession, quality: quality, playbackRate: playbackRate,
                       sequence: sequence, inlinePreview: inlinePreview))
    }

    public init(
        playback: @escaping @MainActor @Sendable (PlaybackTelemetryEvent) -> Void = { _ in },
        click: @escaping @MainActor @Sendable (VideoSummary) -> Void = { _ in }
    ) {
        self.playback = playback
        self.click = click
    }
}
