import XCTest
@testable import NeoBili

@MainActor
final class HomeFeedLayoutTests: XCTestCase {
    private func video(_ id: Int) -> VideoSummary {
        VideoSummary(bvid: "BV\(id)", aid: id, cid: id, title: "视频", pic: "", desc: "", duration: 1,
                     pubdate: 1, owner: VideoOwner(mid: 42, name: "UP", face: ""),
                     stat: VideoStat(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0),
                     recommendationTrackID: "track-\(id)")
    }

    func testRefreshMarkerOccupiesOwnRowAtOddBoundary() {
        let rows = HomeFeedRow.group([.video(video(1)), .video(video(2)), .video(video(3)),
                                      .lastSeen, .video(video(4)), .video(video(5))])
        XCTAssertEqual(rows.map(\.id), ["row-BV1", "row-BV3", "last-seen-row", "row-BV4"])
        guard case .videos(let before) = rows[1], case .videos(let after) = rows[3] else {
            return XCTFail("分界两侧应保留独立视频行")
        }
        XCTAssertEqual(before.map(\.aid), [3])
        XCTAssertEqual(after.map(\.aid), [4, 5])
    }

    func testRecommendationFeedbackRetainsTrackingAndContentReason() {
        let form = BiliAPI.recommendationFeedbackForm(video(123))
        XCTAssertEqual(form["track_id"], "track-123")
        XCTAssertEqual(form["id"], "123")
        XCTAssertEqual(form["mid"], "42")
        XCTAssertEqual(form["reason_id"], "1")
    }

    func testSuccessfulFeedbackIsSubmittedOnce() async {
        var calls = 0
        let model = HomeViewModel(reportUninterested: { _ in calls += 1 })
        let error = await model.markUninterested(video(1))
        XCTAssertNil(error)
        _ = await model.markUninterested(video(1))
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(model.uninterestedIDs.contains("BV1"))
        XCTAssertTrue(model.reportingIDs.isEmpty)
    }

    func testFailedFeedbackDoesNotReplaceCard() async {
        let model = HomeViewModel(reportUninterested: { _ in throw URLError(.notConnectedToInternet) })
        let error = await model.markUninterested(video(1))
        XCTAssertNotNil(error)
        XCTAssertTrue(model.uninterestedIDs.isEmpty)
        XCTAssertTrue(model.reportingIDs.isEmpty)
    }
}
