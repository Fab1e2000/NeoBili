import Foundation

    public struct RecommendationExposureCard {
        public let video: VideoSummary
        public let position: Int
        public var visibleRatio: Double = 1
        public var key: String { "\(video.playbackEntry.loginSessionID?.uuidString ?? "")|\(video.playbackEntry.trackID ?? "")|\(video.bvid)" }

        public init(
            video: VideoSummary,
            position: Int,
            visibleRatio: Double = 1
        ) {
            self.video = video
            self.position = position
            self.visibleRatio = visibleRatio
        }
    }
    public struct RecommendationExposureEvent {
        public let card: RecommendationExposureCard
        public let name: String
        public let timestamp: Int
        public let start: Int?
        public let end: Int?

        public init(
            card: RecommendationExposureCard,
            name: String,
            timestamp: Int,
            start: Int? = nil,
            end: Int? = nil
        ) {
            self.card = card
            self.name = name
            self.timestamp = timestamp
            self.start = start
            self.end = end
        }
    }
