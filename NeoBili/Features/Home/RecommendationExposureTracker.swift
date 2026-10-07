import Foundation

/// Owns show deduplication and separate duration intervals, driven by visible area.
/// Prefetch and cell creation never count as exposure.
@MainActor
final class RecommendationExposureTracker {
    struct Card {
        let video: VideoSummary
        let position: Int
        var visibleRatio: Double = 1
        var key: String { "\(video.playbackEntry.loginSessionID?.uuidString ?? "")|\(video.playbackEntry.trackID ?? "")|\(video.bvid)" }
    }
    struct Event {
        let card: Card
        let name: String
        let timestamp: Int
        let start: Int?
        let end: Int?
    }
    private struct Interval { let card: Card; let start: Int; let minimumMilliseconds: Int }
    private var visible: [String: Interval] = [:]
    private var seen: Set<String> = []
    private let emit: @MainActor (Event) -> Void

    init(emit: @escaping @MainActor (Event) -> Void = RecommendationExposureTracker.record) { self.emit = emit }

    func update(_ cards: [Card], timestamp: Int, policy: RecommendationExposurePolicy = .init()) {
        let next = Dictionary(cards.filter { $0.visibleRatio.isFinite && $0.visibleRatio > 0 }
            .map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        // Existing intervals survive equality at the end threshold (hysteresis).
        for (key, interval) in visible where next[key] == nil || next[key]!.visibleRatio < policy.durationEndRatio {
            let end = max(timestamp, interval.start)
            if Double(end) - Double(interval.start) >= Double(interval.minimumMilliseconds) {
                emit(.init(card: interval.card, name: "tm.recommend.feed-card.duration.show",
                           timestamp: timestamp, start: interval.start, end: end))
            }
            visible.removeValue(forKey: key)
        }
        for (key, card) in next {
            if card.visibleRatio >= policy.showRatio, seen.insert(key).inserted {
                emit(.init(card: card, name: "tm.recommend.feed-card.0.show", timestamp: timestamp, start: nil, end: nil))
            }
            if visible[key] == nil, card.visibleRatio >= policy.durationStartRatio {
                visible[key] = Interval(card: card, start: timestamp,
                                       minimumMilliseconds: policy.minimumDurationMilliseconds)
            }
        }
        if seen.count > 2000 { seen = Set(visible.keys) }
    }

    private static func record(_ event: Event) {
        guard !AppNetwork.isRegression,
              let session = event.card.video.playbackEntry.loginSessionID,
              session == DeviceIdentity.shared.loginSessionID,
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
