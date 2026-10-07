import XCTest
@testable import NeoBili

@MainActor
final class RecommendationExposurePolicyTests: XCTestCase {
    func testConfigDefaultsAndIndependentThresholds() throws {
        let defaults = try JSONDecoder().decode(RecommendationExposurePolicy.self, from: Data("{}".utf8))
        XCTAssertEqual(defaults, .init())
        let decoded = try JSONDecoder().decode(RecommendationExposurePolicy.self, from: Data("""
            {"exposure_duration_start_ratio":0.9,"exposure_duration_end_ratio":0.6,
             "exposure_duration_min_ms":1250,"visible_area":35}
            """.utf8))
        XCTAssertEqual(decoded, .init(durationStartRatio: 0.9, durationEndRatio: 0.6,
                                     minimumDurationMilliseconds: 1250, showRatio: 0.35))
        let invalid = try JSONDecoder().decode(RecommendationExposurePolicy.self, from: Data("""
            {"exposure_duration_start_ratio":"0.2","exposure_duration_end_ratio":null,
             "exposure_duration_min_ms":"100","visible_area":false}
            """.utf8))
        XCTAssertEqual(invalid, defaults)
    }

    func testPartialVisibilityShowsButDoesNotBeginDuration() {
        var events: [RecommendationExposureTracker.Event] = []
        let tracker = RecommendationExposureTracker { events.append($0) }
        tracker.update([card(ratio: 0)], timestamp: 0)
        XCTAssertTrue(events.isEmpty)
        tracker.update([card(ratio: 0.01)], timestamp: 100)
        tracker.update([], timestamp: 1000)
        XCTAssertEqual(events.map(\.name), ["tm.recommend.feed-card.0.show"])
        tracker.update([card(ratio: 0.8)], timestamp: 2000)
        tracker.update([], timestamp: 3000)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[1].start, 2000)
        XCTAssertEqual(events[1].end, 3000)
    }

    func testHysteresisEqualityAndMinimumDuration() {
        var events: [RecommendationExposureTracker.Event] = []
        let tracker = RecommendationExposureTracker { events.append($0) }
        let policy = RecommendationExposurePolicy(durationStartRatio: 0.8, durationEndRatio: 0.5,
                                                  minimumDurationMilliseconds: 1000, showRatio: 0.2)
        tracker.update([card(ratio: 0.7)], timestamp: 0, policy: policy)
        tracker.update([card(ratio: 0.8)], timestamp: 100, policy: policy)
        tracker.update([card(ratio: 0.5)], timestamp: 900, policy: policy)
        XCTAssertEqual(events.count, 1)
        tracker.update([card(ratio: 0.49)], timestamp: 1100, policy: policy)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[1].start, 100)
        XCTAssertEqual(events[1].end, 1100)
        tracker.update([card(ratio: 1)], timestamp: 2000, policy: policy)
        tracker.update([], timestamp: 2999, policy: policy)
        XCTAssertEqual(events.count, 2, "Intervals shorter than min_ms must not report, even on leaving the screen")
        tracker.update([card(ratio: 1)], timestamp: 4000, policy: policy)
        tracker.update([], timestamp: 5000, policy: policy)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[2].start, 4000)
    }

    func testDurationCanStartBeforeShowThresholdAndExitWithoutShow() {
        var events: [RecommendationExposureTracker.Event] = []
        let tracker = RecommendationExposureTracker { events.append($0) }
        let policy = RecommendationExposurePolicy(showRatio: 0.95)
        tracker.update([card(ratio: 0.8)], timestamp: 0, policy: policy)
        tracker.update([], timestamp: 20, policy: policy)
        XCTAssertEqual(events.map(\.name), ["tm.recommend.feed-card.duration.show"])
        tracker.update([card(ratio: 1)], timestamp: 30, policy: policy)
        XCTAssertEqual(events.last?.name, "tm.recommend.feed-card.0.show")
    }

    private func card(ratio: Double) -> RecommendationExposureTracker.Card {
        var video = VideoSummary(bvid: "exposure-fixture", aid: 1, cid: 2, title: "Fixture", pic: "", desc: "",
            duration: 100, pubdate: 0, owner: .init(mid: 1, name: "", face: ""),
            stat: .init(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0))
        video.playbackEntry = .init(source: .recommendation, trackID: "fixture-batch")
        return .init(video: video, position: 1, visibleRatio: ratio)
    }
}
