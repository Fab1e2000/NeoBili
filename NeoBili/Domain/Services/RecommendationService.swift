import Foundation

/// Recommendation operations available to application state and views.
/// Values can be replaced per model or view hierarchy without changing global state.
struct RecommendationService: Sendable {
    var recommendFeedOperation: @Sendable (RecommendationRequest) async throws -> RecommendationBatch = { _ in throw ServiceError.unconfigured("Recommendation.recommendFeed") }
    var feedDislikeOperation: @Sendable (RecommendationFeedbackOptions, RecommendationFeedbackOptions.Reason, UUID?) async throws -> Void = { _, _, _ in throw ServiceError.unconfigured("Recommendation.feedDislike") }
    var feedDislikeCancelOperation: @Sendable (RecommendationFeedbackOptions, UUID?) async throws -> Void = { _, _ in throw ServiceError.unconfigured("Recommendation.feedDislikeCancel") }
    var feedbackOptionsOperation: @Sendable (VideoSummary, UUID) throws -> RecommendationFeedbackOptions? = { _, _ in throw ServiceError.unconfigured("Recommendation.feedbackOptions") }

    func recommendFeed(request: RecommendationRequest) async throws -> RecommendationBatch {
        try await recommendFeedOperation(request)
    }

    func feedDislike(_ options: RecommendationFeedbackOptions, reason: RecommendationFeedbackOptions.Reason, expectedSessionID: UUID? = nil) async throws {
        try await feedDislikeOperation(options, reason, expectedSessionID)
    }

    func feedDislikeCancel(_ options: RecommendationFeedbackOptions, expectedSessionID: UUID? = nil) async throws {
        try await feedDislikeCancelOperation(options, expectedSessionID)
    }

    func feedbackOptions(for video: VideoSummary, expectedSessionID: UUID) throws -> RecommendationFeedbackOptions? {
        try feedbackOptionsOperation(video, expectedSessionID)
    }
}
