import Foundation

extension RecommendationService {
    static func live(client: APIClient = .shared) -> Self {
        Self(
            recommendFeedOperation: { request in
                try await BiliAPI.recommendFeed(request: request)
            },
            feedDislikeOperation: { options, reason, expectedSessionID in
                try await BiliAPI.feedDislike(options, reason: reason, expectedSessionID: expectedSessionID, client: client)
            },
            feedDislikeCancelOperation: { options, expectedSessionID in
                try await BiliAPI.feedDislikeCancel(options, expectedSessionID: expectedSessionID, client: client)
            },
            feedbackOptionsOperation: { video, expectedSessionID in
                try BiliAPI.feedbackOptions(for: video, expectedSessionID: expectedSessionID)
            }
        )
    }
}
