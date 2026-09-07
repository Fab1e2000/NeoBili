import XCTest
@testable import NeoBili

@MainActor
final class PortraitVideoFilterTests: XCTestCase {
    func testStrictPortraitClassificationUsesPresentedAxes() {
        XCTAssertTrue(VideoDimension(width: 1080, height: 1920).isPortrait)
        XCTAssertFalse(VideoDimension(width: 1920, height: 1080).isPortrait)
        XCTAssertFalse(VideoDimension(width: 1080, height: 1080).isPortrait)
        XCTAssertFalse(VideoDimension(width: 0, height: 1920).isPortrait)

        XCTAssertTrue(VideoDimension(width: 1920, height: 1080, rotate: 90).isPortrait)
        XCTAssertFalse(VideoDimension(width: 1080, height: 1920, rotate: 270).isPortrait)
    }

    func testFilterHidesOnlyKnownPortraitVideos() {
        let portrait = video("portrait", dimension: .init(width: 720, height: 1280))
        let landscape = video("landscape", dimension: .init(width: 1280, height: 720))
        let square = video("square", dimension: .init(width: 720, height: 720))
        let unknown = video("unknown", dimension: nil)
        let videos = [portrait, landscape, square, unknown]

        XCTAssertEqual(videos.hidingKnownPortraitVideos(false).map(\.bvid), videos.map(\.bvid))
        XCTAssertEqual(
            videos.hidingKnownPortraitVideos(true).map(\.bvid),
            ["landscape", "square", "unknown"]
        )
    }

    func testDimensionDecodesNumbersAndNumericStrings() throws {
        let data = Data(#"{"width":"1080","height":1920,"rotate":"0"}"#.utf8)
        let dimension = try JSONDecoder().decode(VideoDimension.self, from: data)

        XCTAssertEqual(dimension, VideoDimension(width: 1080, height: 1920))
        XCTAssertTrue(dimension.isPortrait)
    }

    func testVideoSummaryDecodesListDimension() throws {
        let data = Data(#"{"bvid":"BV1","aid":1,"cid":2,"title":"竖屏","pic":"","desc":"","duration":10,"pubdate":1,"owner":{"mid":3,"name":"UP","face":""},"stat":{"view":0,"danmaku":0,"like":0,"favorite":0,"coin":0,"share":0,"reply":0},"dimension":{"width":720,"height":1280,"rotate":0}}"#.utf8)
        let video = try JSONDecoder().decode(VideoSummary.self, from: data)

        XCTAssertTrue(video.dimension?.isPortrait == true)
    }

    private func video(_ id: String, dimension: VideoDimension?) -> VideoSummary {
        VideoSummary(
            bvid: id,
            aid: 1,
            cid: 1,
            title: id,
            pic: "",
            desc: "",
            duration: 1,
            pubdate: 1,
            owner: VideoOwner(mid: 1, name: "UP", face: ""),
            stat: VideoStat(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0),
            dimension: dimension
        )
    }
}
