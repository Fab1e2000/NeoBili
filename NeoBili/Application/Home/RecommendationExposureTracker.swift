import Foundation

/// Owns show deduplication and separate duration intervals, driven by visible area.
/// Prefetch and cell creation never count as exposure.
@MainActor
final class RecommendationExposureTracker {
    typealias Card = RecommendationExposureCard
    typealias Event = RecommendationExposureEvent
    private struct Interval { let card: Card; let start: Int; let minimumMilliseconds: Int }
    private var visible: [String: Interval] = [:]
    private var seen: Set<String> = []
    private let emit: @MainActor (Event) -> Void

    init(emit: @escaping @MainActor (Event) -> Void = ApplicationServices.recordExposure) { self.emit = emit }

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

}
