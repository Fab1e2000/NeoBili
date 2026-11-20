#if NEOBILI_REGRESSION
#if canImport(NeoBiliDomain)
@testable import NeoBiliDomain
#endif
import XCTest
@testable import NeoBili

@MainActor
final class FilteredVideosMemoTests: XCTestCase {
    private func filtering() -> VideoFilterDependencies {
        VideoFilterDependencies(
            duration: VideoDurationFilterSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            metadata: PortraitVideoStore(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                metadataLoader: { _ in throw URLError(.cannotConnectToHost) }))
    }

    private func video(_ bvid: String, duration: Int = 60) -> VideoSummary {
        VideoSummary(bvid: bvid, aid: 1, cid: 1, title: bvid, pic: "", desc: "", duration: duration,
                     pubdate: 0, owner: VideoOwner(mid: 1, name: "UP", face: ""),
                     stat: VideoStat(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0))
    }

    /// 输入不变时复用缓存，关闭过滤且最低时长为 0 时原样放行。
    func testRepeatedEvaluationReusesCachedResult() {
        let memo = FilteredVideosMemo<VideoSummary>()
        let filtering = filtering()
        let videos = [video("BVone"), video("BVtwo")]

        let first = memo.videos(videos, revision: 0, hidesPortraitVideos: false, filtering: filtering)
        XCTAssertEqual(first.map(\.bvid), ["BVone", "BVtwo"])
        XCTAssertEqual(memo.recomputationCount, 1)

        let second = memo.videos(videos, revision: 0, hidesPortraitVideos: false, filtering: filtering)
        XCTAssertEqual(second.map(\.bvid), ["BVone", "BVtwo"])
        XCTAssertEqual(memo.recomputationCount, 1, "unchanged inputs reuse the cached result")
    }

    /// 内容版本或过滤开关变化时重算。
    func testRevisionOrFilterChangeRecomputes() {
        let memo = FilteredVideosMemo<VideoSummary>()
        let filtering = filtering()
        let videos = [video("BVone")]

        _ = memo.videos(videos, revision: 0, hidesPortraitVideos: false, filtering: filtering)
        XCTAssertEqual(memo.recomputationCount, 1)

        _ = memo.videos(videos, revision: 1, hidesPortraitVideos: false, filtering: filtering)
        XCTAssertEqual(memo.recomputationCount, 2, "a content revision change recomputes")

        _ = memo.videos(videos, revision: 1, hidesPortraitVideos: true, filtering: filtering)
        XCTAssertEqual(memo.recomputationCount, 3, "a filter change recomputes")
    }
}
#endif
