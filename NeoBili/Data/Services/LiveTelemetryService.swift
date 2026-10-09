import Foundation

extension TelemetryService {
    static let live = Self(playback: { event in
        AppPlayerBehavior.record(event.name, aid: event.aid, cid: event.cid, position: event.position,
            playbackSession: event.playbackSession, source: event.source, accountSession: event.accountSession,
            quality: event.quality, playbackRate: event.playbackRate, sequence: event.sequence, inlinePreview: event.inlinePreview)
    }, click: { RecommendationClickReporter.record($0) })
}
