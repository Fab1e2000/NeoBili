import Foundation

extension TelemetryService {
    static var live: Self { live(identity: .shared, reporter: .shared, clickReporter: .shared) }

    static func live(identity: DeviceIdentity, reporter: AppBehaviorReporter, clickReporter: RecommendationClickReporter) -> Self {
        Self(playback: { event in
            AppPlayerBehavior.record(event.name, aid: event.aid, cid: event.cid, position: event.position,
                playbackSession: event.playbackSession, source: event.source, accountSession: event.accountSession,
                quality: event.quality, playbackRate: event.playbackRate, sequence: event.sequence, inlinePreview: event.inlinePreview, reporter: reporter)
        }, click: { RecommendationClickReporter.record($0, identity: identity, reporter: clickReporter) })
    }
}
