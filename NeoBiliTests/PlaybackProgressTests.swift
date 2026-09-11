import XCTest
@testable import NeoBili

@MainActor
final class PlaybackProgressTests: XCTestCase {
    private func makeStore() throws -> PlaybackProgressStore {
        let suite = "neobili.resume.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return PlaybackProgressStore(defaults: defaults)
    }

    private func makePlayer(store: PlaybackProgressStore, cid: Int = 1) -> PlayerViewModel {
        PlayerViewModel(bvid: "BVResumeTest", cid: cid,
                        playbackURLLoader: { _, _ in throw URLError(.notConnectedToInternet) },
                        watchProgressReporter: { _, _, _ in }, progressStore: store)
    }

    func testExitAndReentryResumeWithoutDependingOnNetwork() throws {
        let store = try makeStore()
        let first = makePlayer(store: store)
        first.session.onEvent?(.firstFrame)
        first.session.onEvent?(.duration(300))
        first.session.onEvent?(.position(47.25))
        first.stop()

        let reopened = makePlayer(store: store)
        defer { reopened.stop() }
        XCTAssertEqual(reopened.currentTime, 47.25)
        XCTAssertEqual(store.resumePosition(bvid: "BVResumeTest", cid: 2), 0)
    }

    func testClosingDuringLoadingDoesNotEraseSavedPosition() throws {
        let store = try makeStore()
        store.save(bvid: "BVResumeTest", cid: 1, position: 90, duration: 300)
        let player = makePlayer(store: store)
        player.session.onEvent?(.position(0))
        player.session.onEvent?(.playing(false))
        player.savePlaybackProgress()
        player.stop()
        XCTAssertEqual(store.resumePosition(bvid: "BVResumeTest", cid: 1), 90)
    }

    func testTransientZeroAfterFirstFrameCannotEraseResumePoint() throws {
        let store = try makeStore()
        store.save(bvid: "BVResumeTest", cid: 1, position: 90, duration: 300)
        let player = makePlayer(store: store)
        defer { player.stop() }
        player.session.onEvent?(.firstFrame)
        player.session.onEvent?(.position(0))
        XCTAssertEqual(player.currentTime, 90)
        player.session.onEvent?(.seekCompleted(93.5))
        player.session.onEvent?(.position(94))
        XCTAssertEqual(player.currentTime, 94)
    }

    func testSeekIsSavedImmediatelyAndStaleEventIsRejected() async throws {
        let store = try makeStore()
        let player = makePlayer(store: store)
        defer { player.stop() }
        player.session.onEvent?(.firstFrame)
        player.session.onEvent?(.duration(300))
        player.session.onEvent?(.position(80))
        await player.seek(to: 12)
        player.session.onEvent?(.position(80))
        XCTAssertEqual(player.currentTime, 12)
        XCTAssertEqual(store.resumePosition(bvid: "BVResumeTest", cid: 1), 12)
        await player.seek(to: 0)
        XCTAssertEqual(store.resumePosition(bvid: "BVResumeTest", cid: 1), 0)
    }

    func testBackgroundCheckpointAndPauseCaptureLessThanHeartbeatInterval() throws {
        let store = try makeStore()
        let player = makePlayer(store: store)
        defer { player.stop() }
        player.session.onEvent?(.firstFrame)
        player.session.onEvent?(.position(2.25))
        player.savePlaybackProgress()
        XCTAssertEqual(store.resumePosition(bvid: "BVResumeTest", cid: 1), 2.25)
        player.session.onEvent?(.playing(true))
        player.session.onEvent?(.position(3.75))
        player.togglePlayPause()
        XCTAssertEqual(store.resumePosition(bvid: "BVResumeTest", cid: 1), 3.75)
    }

    func testCompletionSurvivesTrailingEventsAndStop() throws {
        let store = try makeStore()
        let player = makePlayer(store: store)
        player.session.onEvent?(.firstFrame)
        player.session.onEvent?(.position(95))
        player.session.onEvent?(.ended)
        player.session.onEvent?(.position(96))
        player.session.onEvent?(.seekCompleted(0))
        player.stop()
        XCTAssertEqual(store.resumePosition(bvid: "BVResumeTest", cid: 1), 0)
    }

    func testFailedRetryRetainsLastPositionAndPersistentRecord() async throws {
        let store = try makeStore()
        let player = makePlayer(store: store)
        let oldCallback = player.session.onEvent
        player.session.surfacePresentation = .mini
        defer { player.stop() }
        oldCallback?(.firstFrame)
        oldCallback?(.position(23))
        oldCallback?(.error("connection lost"))
        await player.retry()
        oldCallback?(.position(0))
        XCTAssertEqual(player.currentTime, 23)
        XCTAssertEqual(store.resumePosition(bvid: "BVResumeTest", cid: 1), 23)
        XCTAssertNotNil(player.errorMessage)
        XCTAssertEqual(player.session.surfacePresentation, .mini, "重试替换内核必须保留小窗渲染归属")
    }

    func testBackupStreamPreservesMiniSurfaceOwner() async throws {
        let payload = PlayURLData(quality: 64, acceptQuality: [64], acceptDescription: nil,
            durl: [DurlItem(url: "https://example.invalid/primary.mp4",
                            backupUrl: ["https://example.invalid/backup.mp4"], length: 300_000, size: nil)],
            dash: nil, vVoucher: nil)
        let player = PlayerViewModel(bvid: "BVResumeTest", cid: 1,
            playbackURLLoader: { _, _ in payload }, watchProgressReporter: { _, _, _ in },
            progressStore: try makeStore(), sourceOpener: { _, _, _ in })
        defer { player.stop() }
        await player.load()
        let firstSession = player.session
        firstSession.surfacePresentation = .mini
        firstSession.onEvent?(.error("try backup"))
        XCTAssertFalse(firstSession === player.session)
        XCTAssertEqual(player.session.surfacePresentation, .mini)
    }

    func testLoadPassesPersistedPositionToEngineAndEOFScrubReopensPausedFile() async throws {
        let store = try makeStore()
        store.save(bvid: "BVResumeTest", cid: 1, position: 47.25, duration: 300)
        let payload = PlayURLData(quality: 64, acceptQuality: [64], acceptDescription: ["高清"],
                                  durl: [DurlItem(url: "https://example.com/video.mp4", backupUrl: nil,
                                                  length: 300_000, size: nil)],
                                  dash: nil, vVoucher: nil)
        var openedPositions: [TimeInterval] = []
        let player = PlayerViewModel(bvid: "BVResumeTest", cid: 1,
                                    playbackURLLoader: { _, _ in payload },
                                    watchProgressReporter: { _, _, _ in }, progressStore: store,
                                    sourceOpener: { _, _, position in openedPositions.append(position) })
        defer { player.stop() }
        await player.load()
        XCTAssertEqual(openedPositions, [47.25], "保存位置必须真正传给内核开流")
        player.session.onEvent?(.firstFrame)
        player.session.onEvent?(.seekCompleted(47.25))
        player.session.onEvent?(.ended)
        await player.seek(to: 42)
        XCTAssertEqual(openedPositions, [47.25, 42], "EOF 后拖动必须重新打开已卸载的视频文件")
        XCTAssertEqual(player.currentTime, 42)
        XCTAssertFalse(player.isPlaying, "原来已暂停的 EOF 拖动仍保持暂停")
        XCTAssertEqual(store.resumePosition(bvid: "BVResumeTest", cid: 1), 42)
        player.session.onEvent?(.firstFrame)
        player.session.onEvent?(.seekCompleted(42))
        player.play()
        XCTAssertTrue(player.isPlaying)
    }
}
