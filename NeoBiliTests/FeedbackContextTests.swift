import XCTest
@testable import NeoBili

@MainActor
final class FeedbackContextTests: XCTestCase {
    private let reason = RecommendationFeedbackOptions.Reason(id: 17, name: "不感兴趣", toast: nil)

    private func card(session: UUID) -> VideoSummary {
        var video = VideoSummary(bvid: "BVfeedback", aid: 123, cid: 456, title: "fixture", pic: "", desc: "",
            duration: 120, pubdate: 0, owner: .init(mid: 789, name: "Uploader", face: ""),
            stat: .init(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0))
        video.playbackEntry = .recommendation(trackID: "fixture-track", reportFlowData: "not-a-feedback-field")
        video.playbackEntry.loginSessionID = session
        video.recommendationClickFields = ["rid": "42", "tid": "99"]
        video.recommendationFeedback = .init(goto: "av", param: 123, dislikeReasons: [reason])
        return video
    }

    func testFeedbackCarriesOriginalAttributionAndUploaderIdentity() throws {
        let session = UUID()
        let options = try XCTUnwrap(BiliAPI.feedbackOptions(for: card(session: session), expectedSessionID: session))
        let fields = BiliAPI.feedbackParameters(options)
        XCTAssertEqual(fields["id"], "123")
        XCTAssertEqual(fields["goto"], "av")
        XCTAssertEqual(fields["track_id"], "fixture-track")
        XCTAssertEqual(fields["from_spmid"], "tm.recommend.0.0")
        XCTAssertEqual(fields["mid"], "789")
        XCTAssertEqual(fields["rid"], "42")
        XCTAssertNil(fields["tag_id"], "Do not guess that category tid is the feedback tag ID")
        XCTAssertNil(fields["report_flow_data"])
        XCTAssertEqual(options.requestContext?.loginSessionID, session)
    }

    func testOldCardCannotBeReboundToNewLogin() throws {
        let original = UUID(), current = UUID()
        var video = card(session: original)
        XCTAssertThrowsError(try BiliAPI.feedbackOptions(for: video, expectedSessionID: current))
        video.recommendationFeedback = try BiliAPI.feedbackOptions(for: video, expectedSessionID: original)
        // Even if a caller accidentally overwrites playback routing, the feedback keeps its origin.
        video.playbackEntry.loginSessionID = current
        XCTAssertThrowsError(try BiliAPI.feedbackOptions(for: video, expectedSessionID: current))
    }

    func testStaleCardMenuDoesNotSubmitOrUndo() async {
        let original = UUID(), current = UUID()
        let name = "FeedbackContextTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var submissions = 0, cancellations = 0
        let model = HomeViewModel(defaults: defaults,
            reportUninterested: { _, _ in submissions += 1 },
            cancelUninterested: { _ in cancellations += 1 },
            currentSessionID: { current })
        let submitted = await model.markUninterested(card(session: original), reason: reason)
        let cancelled = await model.cancelUninterested(card(session: original))
        XCTAssertNil(submitted)
        XCTAssertNil(cancelled)
        XCTAssertEqual(submissions, 0)
        XCTAssertEqual(cancellations, 0)
    }

    func testBothDirectFeedbackAPIsRejectMismatchedGenerationBeforeNetwork() async throws {
        let original = UUID(), current = UUID()
        let options = try XCTUnwrap(BiliAPI.feedbackOptions(for: card(session: original), expectedSessionID: original))
        do {
            try await BiliAPI.feedDislike(options, reason: reason, expectedSessionID: current)
            XCTFail("Old login context must not be sent")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        do {
            try await BiliAPI.feedDislikeCancel(options, expectedSessionID: current)
            XCTFail("Old login undo must not be sent")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
}
