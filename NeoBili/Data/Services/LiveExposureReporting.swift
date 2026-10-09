import Foundation

@MainActor
enum LiveExposureReporting {
    static func record(_ event: RecommendationExposureEvent) {
        guard !AppNetwork.isRegression,
              let session = event.card.video.playbackEntry.loginSessionID,
              session == ApplicationServices.live.session.currentID(),
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
        Task { await AppBehaviorReporter.shared.record(name: event.name, category: 3, fields: values,
            session: session, timestamp: event.timestamp) }
    }
}
