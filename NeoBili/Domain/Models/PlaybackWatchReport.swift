import Foundation

struct PlaybackWatchReport: Sendable {
    enum Delivery: Sendable, Equatable { case start, checkpoint, finish }
    let position: Double
    let watchedTime: Double
    let pausedTime: Double
    let maximumPosition: Double
    let duration: Double
    var startTimestamp: Int
    let sourceFields: [String: String]
    var playbackSession: String = ""
    var aid: Int = 0
    var miniPlayerTime: Double = 0
    var delivery: Delivery = .finish
    var localStartTimestamp: Int? = nil
    var isInlinePreview = false
    /// Nil preserves 1x semantics for manually constructed reports.
    var actualPlayedTime: Double? = nil

}
