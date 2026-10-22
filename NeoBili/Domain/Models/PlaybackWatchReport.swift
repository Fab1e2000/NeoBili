import Foundation

public struct PlaybackWatchReport: Sendable {
    public enum Delivery: Sendable, Equatable { case start, checkpoint, finish }
    public let position: Double
    public let watchedTime: Double
    public let pausedTime: Double
    public let maximumPosition: Double
    public let duration: Double
    public var startTimestamp: Int
    public let sourceFields: [String: String]
    public var playbackSession: String = ""
    public var aid: Int = 0
    public var miniPlayerTime: Double = 0
    public var delivery: Delivery = .finish
    public var localStartTimestamp: Int? = nil
    public var isInlinePreview = false
    /// Nil preserves 1x semantics for manually constructed reports.
    public var actualPlayedTime: Double? = nil

    public init(
        position: Double,
        watchedTime: Double,
        pausedTime: Double,
        maximumPosition: Double,
        duration: Double,
        startTimestamp: Int,
        sourceFields: [String: String],
        playbackSession: String = "",
        aid: Int = 0,
        miniPlayerTime: Double = 0,
        delivery: Delivery = .finish,
        localStartTimestamp: Int? = nil,
        isInlinePreview: Bool = false,
        actualPlayedTime: Double? = nil
    ) {
        self.position = position
        self.watchedTime = watchedTime
        self.pausedTime = pausedTime
        self.maximumPosition = maximumPosition
        self.duration = duration
        self.startTimestamp = startTimestamp
        self.sourceFields = sourceFields
        self.playbackSession = playbackSession
        self.aid = aid
        self.miniPlayerTime = miniPlayerTime
        self.delivery = delivery
        self.localStartTimestamp = localStartTimestamp
        self.isInlinePreview = isInlinePreview
        self.actualPlayedTime = actualPlayedTime
    }
}
