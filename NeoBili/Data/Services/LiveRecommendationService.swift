#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation

extension RecommendationService {
    static func live(client: APIClient = .shared, identity: DeviceIdentity = .shared,
                              session: AppRecommendationSession = .shared, network: AppNetworkMetadata = .shared,
                              clickReporter: RecommendationClickReporter = .shared,
                              filter: @escaping @Sendable () -> RecommendationFilter = { .current() }) -> Self {
        Self(
            recommendFeedOperation: { request in
                try await BiliAPI.recommendFeed(request: request, client: client, identity: identity, session: session,
                                                network: network, clickReporter: clickReporter, filter: filter)
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
