import Foundation

/// Recommendation operations available to application state and views.
/// Values can be replaced per model or view hierarchy without changing global state.
public struct RecommendationService: Sendable {
    public var recommendFeedOperation: @Sendable (RecommendationRequest) async throws -> RecommendationBatch = { _ in throw ServiceError.unconfigured("Recommendation.recommendFeed") }
    public var feedDislikeOperation: @Sendable (RecommendationFeedbackOptions, RecommendationFeedbackOptions.Reason, UUID?) async throws -> Void = { _, _, _ in throw ServiceError.unconfigured("Recommendation.feedDislike") }
    public var feedDislikeCancelOperation: @Sendable (RecommendationFeedbackOptions, UUID?) async throws -> Void = { _, _ in throw ServiceError.unconfigured("Recommendation.feedDislikeCancel") }
    public var feedbackOptionsOperation: @Sendable (VideoSummary, UUID) throws -> RecommendationFeedbackOptions? = { _, _ in throw ServiceError.unconfigured("Recommendation.feedbackOptions") }

    public func recommendFeed(request: RecommendationRequest) async throws -> RecommendationBatch {
        try await recommendFeedOperation(request)
    }

    public func feedDislike(_ options: RecommendationFeedbackOptions, reason: RecommendationFeedbackOptions.Reason, expectedSessionID: UUID? = nil) async throws {
        try await feedDislikeOperation(options, reason, expectedSessionID)
    }

    public func feedDislikeCancel(_ options: RecommendationFeedbackOptions, expectedSessionID: UUID? = nil) async throws {
        try await feedDislikeCancelOperation(options, expectedSessionID)
    }

    public func feedbackOptions(for video: VideoSummary, expectedSessionID: UUID) throws -> RecommendationFeedbackOptions? {
        try feedbackOptionsOperation(video, expectedSessionID)
    }

    public init(
        recommendFeedOperation: @escaping @Sendable (RecommendationRequest) async throws -> RecommendationBatch = { _ in throw ServiceError.unconfigured("Recommendation.recommendFeed") },
        feedDislikeOperation: @escaping @Sendable (RecommendationFeedbackOptions, RecommendationFeedbackOptions.Reason, UUID?) async throws -> Void = { _, _, _ in throw ServiceError.unconfigured("Recommendation.feedDislike") },
        feedDislikeCancelOperation: @escaping @Sendable (RecommendationFeedbackOptions, UUID?) async throws -> Void = { _, _ in throw ServiceError.unconfigured("Recommendation.feedDislikeCancel") },
        feedbackOptionsOperation: @escaping @Sendable (VideoSummary, UUID) throws -> RecommendationFeedbackOptions? = { _, _ in throw ServiceError.unconfigured("Recommendation.feedbackOptions") }
    ) {
        self.recommendFeedOperation = recommendFeedOperation
        self.feedDislikeOperation = feedDislikeOperation
        self.feedDislikeCancelOperation = feedDislikeCancelOperation
        self.feedbackOptionsOperation = feedbackOptionsOperation
    }
}
