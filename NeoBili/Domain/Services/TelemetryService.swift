import Foundation

struct PlaybackTelemetryEvent: Sendable {
    let name: String
    let aid: Int
    let cid: Int
    let position: Double
    let playbackSession: String
    let source: [String: String]
    let accountSession: UUID
    let quality: Int?
    let playbackRate: Double
    let sequence: Int
    let inlinePreview: Bool
}

struct TelemetryService: Sendable {
    var playback: @MainActor @Sendable (PlaybackTelemetryEvent) -> Void = { _ in }
    var click: @MainActor @Sendable (VideoSummary) -> Void = { _ in }

    @MainActor func record(_ name: String, aid: Int, cid: Int, position: Double, playbackSession: String,
                          source: [String: String], accountSession: UUID, quality: Int?,
                          playbackRate: Double = 1, sequence: Int, inlinePreview: Bool = false) {
        playback(.init(name: name, aid: aid, cid: cid, position: position, playbackSession: playbackSession,
                       source: source, accountSession: accountSession, quality: quality, playbackRate: playbackRate,
                       sequence: sequence, inlinePreview: inlinePreview))
    }
}
