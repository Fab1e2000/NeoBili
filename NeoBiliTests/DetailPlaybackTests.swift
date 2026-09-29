import XCTest
@testable import NeoBili

@MainActor
final class DetailPlaybackTests: XCTestCase {
    private func makeDefaults() throws -> UserDefaults {
        let suite = "neobili.detail-playback.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testAutoPlayDefaultsOnAndStartsForKnownCid() throws {
        let defaults = try makeDefaults()
        XCTAssertTrue(DetailPlaybackSettings.isAutoPlayEnabled(in: defaults))

        let store = NowPlayingStore(defaults: defaults)
        defer { store.close() }
        store.open(VideoDetailRoute(bvid: "BVAutoPlay", cid: 1), from: "card")

        XCTAssertFalse(store.isWaitingForPlayback)
        XCTAssertEqual(store.player?.cid, 1)
    }

    func testManualPlayWaitsThroughPartSelectionAndResetsForNextVideo() throws {
        let defaults = try makeDefaults()
        defaults.set(false, forKey: DetailPlaybackSettings.storageKey)
        let store = NowPlayingStore(defaults: defaults)
        defer { store.close() }

        store.open(VideoDetailRoute(bvid: "BVManualOne", cid: 1), from: "card")
        XCTAssertTrue(store.isWaitingForPlayback)
        XCTAssertNil(store.player)

        store.selectPart(cid: 2)
        XCTAssertNil(store.player)
        store.requestPlayback()
        XCTAssertFalse(store.isWaitingForPlayback)
        XCTAssertEqual(store.player?.cid, 2)

        store.open(VideoDetailRoute(bvid: "BVManualTwo", cid: 3), from: "card")
        XCTAssertTrue(store.isWaitingForPlayback)
        XCTAssertNil(store.player)
        store.togglePlayback()
        XCTAssertEqual(store.player?.cid, 3)
    }

    func testPlayRequestWaitsForCid() throws {
        let defaults = try makeDefaults()
        defaults.set(false, forKey: DetailPlaybackSettings.storageKey)
        let store = NowPlayingStore(defaults: defaults)
        defer { store.close() }

        store.open(VideoDetailRoute(bvid: "BVWithoutCid"), from: "card")
        store.requestPlayback()
        XCTAssertNil(store.player)

        store.selectPart(cid: 4)
        XCTAssertEqual(store.player?.cid, 4)
    }
}
