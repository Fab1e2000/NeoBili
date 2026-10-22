#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation

@MainActor
public enum LiveExposureReporting {
    public static func record(_ event: RecommendationExposureEvent, currentSessionID: UUID, reporter: AppBehaviorReporter) {
        guard !AppNetwork.isRegression,
              let session = event.card.video.playbackEntry.loginSessionID,
              session == currentSessionID,
              let track = event.card.video.playbackEntry.trackID, !track.isEmpty,
              var fields = event.card.video.recommendationClickFields else { return }
        fields["track_id"] = track; fields["event_policy"] = "1"
        fields["position"] = String(event.card.position + (event.name == "tm.recommend.feed-card.duration.show" ? 1 : 0))
        fields["card_goto"] = fields["goto"]
        fields.removeValue(forKey: "up_id")
        if let start = event.start, let end = event.end {
            fields["card_start_time"] = String(start); fields["card_end_time"] = String(end)
        }
        let values = fields
        Task { await reporter.record(name: event.name, category: 3, fields: values,
            session: session, timestamp: event.timestamp) }
    }
}
