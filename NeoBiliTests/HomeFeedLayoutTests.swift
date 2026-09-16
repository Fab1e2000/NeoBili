import XCTest
@testable import NeoBili

@MainActor
final class HomeFeedLayoutTests: XCTestCase {
    func testRefreshRestartsCursorAndPaginationContinuesWithinSession() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(1234, forKey: "neobili.recommendFreshIndex")
        var requested: [Int] = []
        let model = HomeViewModel(defaults: defaults, fetchRecommendations: { index in
            requested.append(index)
            return [self.video(requested.count)]
        })
        await model.loadInitial()
        await model.loadMoreIfNeeded(current: model.videos.last!)
        await model.refresh()
        await model.loadMoreIfNeeded(current: model.videos.last!)
        XCTAssertEqual(requested, [0, 1, 0, 1])
    }

    func testFailedRefreshKeepsContentAndRetriesRecommendationFromZero() async {
        var requested: [Int] = []
        let model = HomeViewModel(fetchRecommendations: { index in
            requested.append(index)
            if requested.count == 2 { throw URLError(.notConnectedToInternet) }
            return [self.video(requested.count)]
        })
        await model.loadInitial()
        await model.refresh()
        XCTAssertEqual(model.videos.map(\.aid), [1])
        XCTAssertNotNil(model.errorMessage)
        await model.refresh()
        XCTAssertEqual(requested, [0, 0, 0])
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.videos.first?.aid, 3)
    }

    func testStagedRefreshDoesNotReplaceCardsBeforeExitCompletes() async {
        var requests = 0
        let model = HomeViewModel(fetchRecommendations: { _ in
            requests += 1
            return [self.video(requests)]
        })
        await model.loadInitial()
        await model.refresh(staged: true)
        XCTAssertEqual(model.videos.first?.aid, 1)
        model.commitStagedRefresh()
        XCTAssertEqual(model.videos.first?.aid, 2)
    }

    func testExitStartsWithRefreshAndOnlyWaitsForRemainingTime() {
        let exit = FeedRefreshExitTiming(start: 10, duration: FeedRefreshTuning.fadeExit(speed: 4))
        XCTAssertEqual(exit.remaining(at: 10), 0.225, accuracy: 0.001)
        XCTAssertEqual(exit.remaining(at: 10.1), 0.125, accuracy: 0.001)
        XCTAssertEqual(exit.remaining(at: 12), 0)
    }

    private func video(_ id: Int) -> VideoSummary {
        VideoSummary(bvid: "BV\(id)", aid: id, cid: id, title: "视频", pic: "", desc: "", duration: 1,
                     pubdate: 1, owner: VideoOwner(mid: 42, name: "UP", face: ""),
                     stat: VideoStat(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0),
                     recommendationTrackID: "track-\(id)")
    }

    func testOddRefreshBoundaryFinishesRowBeforeMarkerWithoutLosingVideos() {
        let rows = HomeFeedRow.group([.video(video(1)), .video(video(2)), .video(video(3)),
                                      .lastSeen, .video(video(4)), .video(video(5))])
        XCTAssertEqual(rows.map(\.id), ["row-BV1", "row-BV3", "last-seen-row", "row-BV5"])
        let videos = rows.flatMap { row -> [VideoSummary] in
            if case .videos(let videos) = row { return videos }
            return []
        }
        XCTAssertEqual(videos.map(\.aid), [1, 2, 3, 4, 5])
        guard case .videos(let before) = rows[1] else { return XCTFail("Expected complete row") }
        XCTAssertEqual(before.map(\.aid), [3, 4])
    }

    func testEvenRefreshBoundaryKeepsMarkerInPlace() {
        let rows = HomeFeedRow.group([.video(video(1)), .video(video(2)), .lastSeen,
                                      .video(video(3)), .video(video(4))])
        XCTAssertEqual(rows.map(\.id), ["row-BV1", "last-seen-row", "row-BV3"])
    }

    func testOddBoundaryWithNoVisibleOldVideosDoesNotLeaveMarkerUnderHalfRow() {
        let rows = HomeFeedRow.group([.video(video(1)), .lastSeen])
        XCTAssertEqual(rows.map(\.id), ["row-BV1"])
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
