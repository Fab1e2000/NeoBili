import XCTest
@testable import NeoBili
@testable import NeoBiliDomain

@MainActor
final class PlaybackModeTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "PlaybackModeTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testPreferencesPersistGlobally() {
        let prefs = PlaybackModePreferences(defaults: defaults)
        XCTAssertFalse(prefs.loopEnabled)
        XCTAssertTrue(prefs.autoAdvanceEnabled)

        prefs.setLoopEnabled(true)
        prefs.setAutoAdvanceEnabled(false)

        let reloaded = PlaybackModePreferences(defaults: defaults)
        XCTAssertTrue(reloaded.loopEnabled)
        XCTAssertFalse(reloaded.autoAdvanceEnabled)
    }

    func testSleepTimerTakesPriorityOverLoopAndAutoAdvance() {
        let action = PlaybackModeSettings.resolveEndAction(
            sleepsAfterVideoEnd: true,
            loopEnabled: true,
            autoAdvanceEnabled: true,
            isOffline: false,
            currentBvid: "BV1",
            currentCid: 1,
            parts: [makePart(cid: 1, page: 1), makePart(cid: 2, page: 2)]
        )
        XCTAssertEqual(action, .sleep)
    }

    func testLoopTakesPriorityOverAutoAdvance() {
        let action = PlaybackModeSettings.resolveEndAction(
            sleepsAfterVideoEnd: false,
            loopEnabled: true,
            autoAdvanceEnabled: true,
            isOffline: false,
            currentBvid: "BV1",
            currentCid: 1,
            parts: [makePart(cid: 1, page: 1), makePart(cid: 2, page: 2)]
        )
        XCTAssertEqual(action, .loop)
    }

    func testMultiPartAutoAdvanceSwitchesPartAndPausesOnLastPart() {
        let parts = [makePart(cid: 10, page: 1), makePart(cid: 20, page: 2)]
        let related = [makeVideo(bvid: "BV_REL")]

        let firstEnd = PlaybackModeSettings.resolveEndAction(
            sleepsAfterVideoEnd: false,
            loopEnabled: false,
            autoAdvanceEnabled: true,
            isOffline: false,
            currentBvid: "BV1",
            currentCid: 10,
            parts: parts,
            related: related
        )
        XCTAssertEqual(firstEnd, .nextPart(cid: 20))

        let lastEnd = PlaybackModeSettings.resolveEndAction(
            sleepsAfterVideoEnd: false,
            loopEnabled: false,
            autoAdvanceEnabled: true,
            isOffline: false,
            currentBvid: "BV1",
            currentCid: 20,
            parts: parts,
            related: related
        )
        XCTAssertEqual(lastEnd, .pause)
    }

    func testSeasonAutoAdvanceSwitchesEpisodeAndPausesOnLastEpisode() {
        let ep1 = UgcSeasonEpisode(episodeId: 1, aid: 1, cid: 11, bvid: "BV1", title: "E1", arc: nil, pages: nil)
        let ep2 = UgcSeasonEpisode(episodeId: 2, aid: 2, cid: 22, bvid: "BV2", title: "E2", arc: nil, pages: nil)
        let season = UgcSeason(id: 99, title: "合集", cover: nil, mid: nil,
                               sections: [UgcSeasonSection(id: 1, title: "正片", episodes: [ep1, ep2])])
        let related = [makeVideo(bvid: "BV_REL")]

        let firstEnd = PlaybackModeSettings.resolveEndAction(
            sleepsAfterVideoEnd: false,
            loopEnabled: false,
            autoAdvanceEnabled: true,
            isOffline: false,
            currentBvid: "BV1",
            currentCid: 11,
            season: season,
            related: related
        )
        XCTAssertEqual(firstEnd, .nextSeasonEpisode(ep2))

        let lastEnd = PlaybackModeSettings.resolveEndAction(
            sleepsAfterVideoEnd: false,
            loopEnabled: false,
            autoAdvanceEnabled: true,
            isOffline: false,
            currentBvid: "BV2",
            currentCid: 22,
            season: season,
            related: related
        )
        XCTAssertEqual(lastEnd, .pause)
    }

    func testSingleVideoAutoAdvanceSkipsVisitedRelated() {
        let v1 = makeVideo(bvid: "BV_OLD")
        let v2 = makeVideo(bvid: "BV_NEW")

        let action = PlaybackModeSettings.resolveEndAction(
            sleepsAfterVideoEnd: false,
            loopEnabled: false,
            autoAdvanceEnabled: true,
            isOffline: false,
            currentBvid: "BV_CUR",
            currentCid: 1,
            related: [v1, v2],
            visitedBvids: ["BV_OLD"]
        )
        XCTAssertEqual(action, .nextRelated(v2))
    }

    func testOfflineAutoAdvanceMovesToNextCachedPartAndPausesAtEnd() {
        let ids = ["BV1:1", "BV1:2"]
        let next = PlaybackModeSettings.resolveEndAction(
            sleepsAfterVideoEnd: false,
            loopEnabled: false,
            autoAdvanceEnabled: true,
            isOffline: true,
            currentBvid: "BV1",
            currentCid: 1,
            offlineEntryIDs: ids,
            currentOfflineEntryID: "BV1:1"
        )
        XCTAssertEqual(next, .nextOfflineEntry(id: "BV1:2"))

        let last = PlaybackModeSettings.resolveEndAction(
            sleepsAfterVideoEnd: false,
            loopEnabled: false,
            autoAdvanceEnabled: true,
            isOffline: true,
            currentBvid: "BV1",
            currentCid: 2,
            offlineEntryIDs: ids,
            currentOfflineEntryID: "BV1:2"
        )
        XCTAssertEqual(last, .pause)
    }

    func testAutoAdvanceLabelReflectsEpisodePresence() {
        XCTAssertEqual(PlaybackModeSettings.autoAdvanceTitle(hasEpisodes: true), "自动切集")
        XCTAssertEqual(PlaybackModeSettings.autoAdvanceTitle(hasEpisodes: false), "自动连播")
    }

    func testHiResPreferenceDefaultsEnabledAndMapsToAudioCeiling() {
        XCTAssertTrue(PlaybackQuality.isHiResEnabled(in: defaults))
        XCTAssertEqual(PlaybackQuality.preferredAudioQuality(hiResEnabled: true), 0)
        XCTAssertEqual(PlaybackQuality.preferredAudioQuality(hiResEnabled: false), PlaybackQuality.nonHiResAudioCeiling)

        PlaybackQuality.setHiResEnabled(false, in: defaults)
        XCTAssertFalse(PlaybackQuality.isHiResEnabled(in: defaults))
    }

    private func makePart(cid: Int, page: Int) -> VideoPart {
        VideoPart(cid: cid, page: page, part: "P\(page)", duration: 120)
    }

    private func makeVideo(bvid: String) -> VideoSummary {
        VideoSummary(
            bvid: bvid, aid: 1, cid: 1, title: bvid, pic: "", desc: "",
            duration: 60, pubdate: 0,
            owner: VideoOwner(mid: 1, name: "UP", face: ""),
            stat: VideoStat(view: 1, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0)
        )
    }
}
