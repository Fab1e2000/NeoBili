import Foundation

    struct RecommendationExposureCard {
        let video: VideoSummary
        let position: Int
        var visibleRatio: Double = 1
        var key: String { "\(video.playbackEntry.loginSessionID?.uuidString ?? "")|\(video.playbackEntry.trackID ?? "")|\(video.bvid)" }
    }
    struct RecommendationExposureEvent {
        let card: RecommendationExposureCard
        let name: String
        let timestamp: Int
        let start: Int?
        let end: Int?
    }
