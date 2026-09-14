import XCTest
@testable import NeoBili

@MainActor
final class MiniPlayerTests: XCTestCase {
    @MainActor
    private final class OwnershipProbe: PlayerSurfaceOwnershipObserver {
        let ownership: PlayerSurfaceOwnership
        private(set) var observed: [PlayerSurfacePresentation] = []

        init(_ ownership: PlayerSurfaceOwnership) { self.ownership = ownership }
        func playerSurfaceOwnershipDidChange() { observed.append(ownership.presentation) }
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "neobili.mini-player.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func route(cid: Int? = 1) -> VideoDetailRoute {
        VideoDetailRoute(bvid: "BVMiniTest-\(UUID().uuidString)", cid: cid, title: "小窗测试")
    }

    // Keep lifecycle tests synchronous. Every store is closed before this main
    // actor turn ends, so its queued metadata/stream loads never start.
    func testCancelledInteractiveExitRetainsPageAndCanDismissAgain() throws {
        for miniEnabled in [true, false] {
            let defaults = try makeDefaults()
            defaults.set(miniEnabled, forKey: PlaybackWindowSettings.storageKey)
            let store = NowPlayingStore(defaults: defaults)
            defer { store.close() }
            store.open(route(), from: "card")
            store.videoPageDidAppear()
            let player = try XCTUnwrap(store.player)
            let source = store.transitionSourceID
            store.videoPageInteractionBegan()
            XCTAssertTrue(store.isVideoPageInteractionInProgress)
            XCTAssertTrue(store.isExpanded)
            XCTAssertFalse(store.isMiniPlayerPresented)
            store.videoPageDidAppear()
            XCTAssertEqual(store.transitionSourceID, source)
            store.dismissVideoPage()
            store.videoPageInteractionEnded(cancelled: true)
            XCTAssertTrue(store.isExpanded)
            XCTAssertFalse(store.isVideoPageInteractionInProgress)
            XCTAssertFalse(store.isVideoPageDismissalInProgress)
            XCTAssertFalse(store.isMiniPlayerPresented)
            XCTAssertNil(store.dismissalPlaybackPhase)
            XCTAssertTrue(store.player === player)
            XCTAssertEqual(player.session.surfacePresentation, .page)
            store.finishDismissal() // A stale completion must not tear down the restored page.
            XCTAssertTrue(store.player === player)
            store.dismissVideoPage()
            store.finishDismissal()
            XCTAssertEqual(store.isMiniPlayerPresented, miniEnabled)
        }
    }

    func testInteractiveCancellationBeforeBindingChangeClearsFrozenLayout() throws {
        let store = NowPlayingStore(defaults: try makeDefaults())
        defer { store.close() }
        store.open(route(), from: "card")
        store.videoPageInteractionBegan()
        XCTAssertNotNil(store.dismissalPlaybackPhase)
        store.videoPageInteractionEnded(cancelled: true)
        XCTAssertNil(store.dismissalPlaybackPhase)
        XCTAssertTrue(store.isExpanded)
        XCTAssertFalse(store.isMiniPlayerPresented)
    }

    func testPreferenceDefaultsToEnabledAndSupportsExplicitOff() throws {
        let defaults = try makeDefaults()
        XCTAssertTrue(PlaybackWindowSettings.isEnabled(in: defaults))
        defaults.set(false, forKey: PlaybackWindowSettings.storageKey)
        XCTAssertFalse(PlaybackWindowSettings.isEnabled(in: defaults))
        defaults.set(true, forKey: PlaybackWindowSettings.storageKey)
        XCTAssertTrue(PlaybackWindowSettings.isEnabled(in: defaults))
    }

    func testDismissalAndExpansionReusePlayerSessionAndPlaybackState() throws {
        let store = NowPlayingStore(defaults: try makeDefaults())
        defer { store.close() }
        let video = route()
        store.open(video, from: "test-card")
        let player = try XCTUnwrap(store.player)
        let session = player.session
        XCTAssertEqual(session.surfacePresentation, .page)
        let rememberedAnchor = CGPoint(x: 0, y: 0.35)
        store.miniPlayerAnchor = rememberedAnchor
        defer {
            // Avoid a watch-history report or a persisted test progress entry.
            session.onEvent?(.seekCompleted(0))
            PlaybackProgressStore.shared.remove(bvid: video.bvid, cid: 1)
        }
        session.onEvent?(.firstFrame)
        session.onEvent?(.duration(300))
        session.onEvent?(.position(37.25))
        session.onEvent?(.playing(true))
        store.section = .comments
        store.isDescriptionExpanded = true

        store.dismissVideoPage()
        XCTAssertFalse(store.isExpanded)
        XCTAssertTrue(store.isMiniPlayerPresented, "The mini player must appear in the dismissal transaction, before onDisappear")
        XCTAssertEqual(session.surfacePresentation, .page, "The shrinking page keeps its video pixels until the native dismissal completes")
        XCTAssertTrue(store.isVideoPageDismissalInProgress)
        XCTAssertTrue(store.player === player)
        XCTAssertTrue(player.session === session)
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(player.currentTime, 37.25)
        XCTAssertEqual(store.miniPlayerAnchor, rememberedAnchor)

        store.finishDismissal()
        XCTAssertFalse(store.isVideoPageDismissalInProgress)
        XCTAssertTrue(store.isMiniPlayerPresented)
        XCTAssertTrue(store.player === player)
        XCTAssertEqual(player.duration, 300)
        XCTAssertTrue(player.hasRenderedFirstFrame)
        XCTAssertEqual(session.surfacePresentation, .mini)
        XCTAssertEqual(store.miniPlayerAnchor, rememberedAnchor)

        store.expandMiniPlayer()
        XCTAssertTrue(store.isExpanded)
        XCTAssertFalse(store.isMiniPlayerPresented)
        XCTAssertEqual(store.transitionSourceID, NowPlayingStore.miniPlayerTransitionSourceID)
        XCTAssertEqual(session.surfacePresentation, .page)
        XCTAssertEqual(store.miniPlayerAnchor, rememberedAnchor)
        XCTAssertTrue(store.player === player)
        XCTAssertTrue(player.session === session)
        XCTAssertEqual(player.currentTime, 37.25)
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(store.route, video)
        XCTAssertEqual(store.section, .comments)
        XCTAssertTrue(store.isDescriptionExpanded)
    }

    func testDisabledOptionPausesThenReleasesOnlyAfterDismissal() throws {
        let defaults = try makeDefaults()
        defaults.set(false, forKey: PlaybackWindowSettings.storageKey)
        let store = NowPlayingStore(defaults: defaults)
        defer { store.close() }
        store.open(route(), from: "test-card")
        let player = try XCTUnwrap(store.player)
        let route = store.route
        let detail = store.detailViewModel
        player.session.onEvent?(.firstFrame)
        player.session.onEvent?(.playing(true))

        store.dismissVideoPage()
        XCTAssertEqual(store.route, route)
        XCTAssertTrue(store.player === player)
        XCTAssertTrue(store.detailViewModel === detail)
        XCTAssertTrue(store.isVideoPageDismissalInProgress)
        XCTAssertEqual(store.dismissalPlaybackPhase, .playing)
        XCTAssertEqual(player.session.surfacePresentation, .page)
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(store.isExpanded)
        XCTAssertFalse(store.isMiniPlayerPresented)
        store.finishDismissal()
        XCTAssertNil(store.route)
        XCTAssertNil(store.player)
        XCTAssertNil(store.detailViewModel)
        XCTAssertNil(store.dismissalPlaybackPhase)
        XCTAssertFalse(store.isVideoPageDismissalInProgress)
        XCTAssertFalse(store.isMiniPlayerPresented)
    }

    func testReopeningDuringDisabledDismissalRestartsCancelledLoadsAndIgnoresOldCompletion() throws {
        let defaults = try makeDefaults()
        defaults.set(false, forKey: PlaybackWindowSettings.storageKey)
        let store = NowPlayingStore(defaults: defaults)
        defer { store.close() }
        let video = route()
        store.open(video, from: "test-card")
        let oldPlayer = try XCTUnwrap(store.player)
        store.dismissVideoPage()
        store.open(video, from: "test-card")
        let newPlayer = try XCTUnwrap(store.player)
        store.finishDismissal()
        XCTAssertFalse(newPlayer === oldPlayer)
        XCTAssertTrue(store.player === newPlayer)
        XCTAssertEqual(store.route, video)
        XCTAssertTrue(store.isExpanded)
        XCTAssertFalse(store.isMiniPlayerPresented)
        XCTAssertNil(store.dismissalPlaybackPhase)
    }

    func testTurningOptionOffWhileFloatingClosesThePlayer() throws {
        let defaults = try makeDefaults()
        let store = NowPlayingStore(defaults: defaults)
        defer { store.close() }
        store.open(route(), from: "test-card")
        let player = try XCTUnwrap(store.player)
        player.session.onEvent?(.playing(true))
        store.dismissVideoPage()
        store.finishDismissal()
        XCTAssertTrue(store.isMiniPlayerPresented)

        defaults.set(false, forKey: PlaybackWindowSettings.storageKey)
        store.applyMiniPlayerSetting()
        XCTAssertNil(store.player)
        XCTAssertNil(store.route)
        XCTAssertFalse(store.isMiniPlayerPresented)
        XCTAssertFalse(player.isPlaying)
    }

    func testExplicitCloseClearsPlaybackAndIgnoresLatePlayerEvents() throws {
        let store = NowPlayingStore(defaults: try makeDefaults())
        defer { store.close() }
        store.open(route(), from: "test-card")
        let player = try XCTUnwrap(store.player)
        player.session.onEvent?(.playing(true))
        store.dismissVideoPage()
        store.finishDismissal()
        store.close()

        XCTAssertNil(store.route)
        XCTAssertNil(store.player)
        XCTAssertNil(store.detailViewModel)
        XCTAssertNil(store.commentsViewModel)
        XCTAssertFalse(store.isExpanded)
        XCTAssertFalse(store.isMiniPlayerPresented)
        XCTAssertFalse(store.canGoBack)
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(player.isLoading)
        player.session.onEvent?(.playing(true))
        XCTAssertFalse(player.isPlaying)
        store.finishDismissal()
        XCTAssertNil(store.route)
        XCTAssertFalse(store.isMiniPlayerPresented)
    }

    func testLateDismissalCannotCollapseTheReopenedVideo() throws {
        let store = NowPlayingStore(defaults: try makeDefaults())
        defer { store.close() }
        let video = route()
        store.open(video, from: "first-card")
        let player = try XCTUnwrap(store.player)
        store.dismissVideoPage()
        store.open(video, from: "second-card")
        store.finishDismissal()

        XCTAssertTrue(store.isExpanded)
        XCTAssertFalse(store.isMiniPlayerPresented)
        XCTAssertTrue(store.player === player)
        XCTAssertEqual(store.route, video)
        XCTAssertEqual(store.transitionSourceID, "second-card")
        XCTAssertEqual(player.session.surfacePresentation, .page)
    }

    func testLateDismissalCannotCloseANewVideo() throws {
        let store = NowPlayingStore(defaults: try makeDefaults())
        defer { store.close() }
        store.open(route(), from: "first-card")
        let oldPlayer = try XCTUnwrap(store.player)
        oldPlayer.session.onEvent?(.playing(true))
        store.dismissVideoPage()
        let next = route(cid: 2)
        store.open(next, from: "next-card")
        let newPlayer = try XCTUnwrap(store.player)
        store.finishDismissal()

        XCTAssertFalse(oldPlayer.isPlaying)
        XCTAssertFalse(oldPlayer === newPlayer)
        XCTAssertTrue(store.player === newPlayer)
        XCTAssertTrue(store.isExpanded)
        XCTAssertFalse(store.isMiniPlayerPresented)
        XCTAssertEqual(store.route, next)
        XCTAssertEqual(newPlayer.session.surfacePresentation, .page)
    }

    func testLoadingRouteIsRetainedBeforeCIDAndPlayerAreAvailable() throws {
        let store = NowPlayingStore(defaults: try makeDefaults())
        defer { store.close() }
        let video = route(cid: nil)
        store.open(video, from: "dynamic-card")
        let detail = try XCTUnwrap(store.detailViewModel)
        XCTAssertNil(store.player)

        store.dismissVideoPage()
        store.finishDismissal()
        XCTAssertFalse(store.isExpanded)
        XCTAssertTrue(store.isMiniPlayerPresented)
        XCTAssertEqual(store.route, video)
        XCTAssertTrue(store.detailViewModel === detail)
        XCTAssertNil(store.player)

        store.expandMiniPlayer()
        XCTAssertTrue(store.isExpanded)
        XCTAssertFalse(store.isMiniPlayerPresented)
        XCTAssertTrue(store.detailViewModel === detail)
    }

    func testWindowSizeUsesFiniteRatiosAndFitsAvailableSpace() {
        let available = CGSize(width: 369, height: 640)
        let landscape = MiniPlayerLayout.size(in: available, aspectRatio: 16.0 / 9)
        let portrait = MiniPlayerLayout.size(in: available, aspectRatio: 9.0 / 16)
        XCTAssertEqual(landscape.width / landscape.height, 16.0 / 9, accuracy: 0.0001)
        XCTAssertEqual(portrait.width / portrait.height, 9.0 / 16, accuracy: 0.0001)
        XCTAssertLessThan(landscape.height, landscape.width)
        XCTAssertGreaterThan(portrait.height, portrait.width)

        for ratio in [Double?.none, .nan, .infinity, -.infinity, 0, -1, 0.01, 100] {
            let size = MiniPlayerLayout.size(in: available, aspectRatio: ratio)
            XCTAssertTrue(size.width.isFinite && size.height.isFinite)
            XCTAssertGreaterThan(size.width, 0)
            XCTAssertGreaterThan(size.height, 0)
            XCTAssertLessThanOrEqual(size.width, available.width)
            XCTAssertLessThanOrEqual(size.height, available.height)
        }
        XCTAssertEqual(MiniPlayerLayout.size(in: .zero, aspectRatio: nil), .zero)
    }

    func testDraggedWindowStaysWithinBoundsAndAnchorRoundTrips() {
        let bounds = CGRect(x: 12, y: 59, width: 369, height: 640)
        let size = MiniPlayerLayout.size(in: bounds.size, aspectRatio: 9.0 / 16)
        for anchor in [CGPoint(x: -2, y: -1), .zero, CGPoint(x: 0.3, y: 0.7), CGPoint(x: 1, y: 1), CGPoint(x: 3, y: 2)] {
            let center = MiniPlayerLayout.center(anchor: anchor, size: size, in: bounds)
            XCTAssertGreaterThanOrEqual(center.x - size.width / 2, bounds.minX - 0.0001)
            XCTAssertGreaterThanOrEqual(center.y - size.height / 2, bounds.minY - 0.0001)
            XCTAssertLessThanOrEqual(center.x + size.width / 2, bounds.maxX + 0.0001)
            XCTAssertLessThanOrEqual(center.y + size.height / 2, bounds.maxY + 0.0001)
            let restored = MiniPlayerLayout.anchor(for: center, size: size, in: bounds)
            XCTAssertEqual(restored.x, min(max(anchor.x, 0), 1), accuracy: 0.0001)
            XCTAssertEqual(restored.y, min(max(anchor.y, 0), 1), accuracy: 0.0001)
        }
    }

    func testDockingAnchorSurvivesServiceHostChangesAndAnotherDismissal() throws {
        let store = NowPlayingStore(defaults: try makeDefaults())
        defer { store.close() }
        store.open(route(), from: "test-card")
        let anchor = CGPoint(x: 0, y: 0.62)
        store.miniPlayerAnchor = anchor
        store.dismissVideoPage()
        XCTAssertTrue(store.isMiniPlayerPresented)
        store.isServiceSheetPresented = true
        XCTAssertEqual(store.miniPlayerAnchor, anchor)
        store.isServiceSheetPresented = false
        XCTAssertEqual(store.miniPlayerAnchor, anchor)
        store.expandMiniPlayer()
        store.dismissVideoPage()
        store.finishDismissal()
        XCTAssertTrue(store.isMiniPlayerPresented)
        XCTAssertEqual(store.miniPlayerAnchor, anchor)
        XCTAssertEqual(store.player?.session.surfacePresentation, .mini)
    }

    func testPlayerCreatedAfterCIDBecomesAvailableInheritsMiniOwnership() throws {
        let store = NowPlayingStore(defaults: try makeDefaults())
        defer { store.close() }
        store.open(route(cid: nil), from: "dynamic-card")
        store.dismissVideoPage()
        XCTAssertTrue(store.isMiniPlayerPresented)
        XCTAssertNil(store.player)
        store.finishDismissal()
        store.selectPart(cid: 7)
        XCTAssertEqual(store.player?.session.surfacePresentation, .mini)
        XCTAssertFalse(store.isExpanded)
    }

    func testPlayerCreatedDuringDismissalKeepsPageOwnershipUntilCompletion() throws {
        let store = NowPlayingStore(defaults: try makeDefaults())
        defer { store.close() }
        store.open(route(cid: nil), from: "dynamic-card")
        store.videoPageDidAppear()
        store.dismissVideoPage()
        store.selectPart(cid: 9)
        let player = try XCTUnwrap(store.player)
        XCTAssertEqual(player.session.surfacePresentation, .page)
        store.finishDismissal()
        XCTAssertEqual(player.session.surfacePresentation, .mini)
        XCTAssertTrue(store.player === player)
    }

    func testRetryReplacesEngineWithoutLosingMiniSurfaceOwnership() async throws {
        let player = PlayerViewModel(bvid: "BVMiniRetry-\(UUID().uuidString)", cid: 1,
                                     playbackURLLoader: { _, _ in throw URLError(.notConnectedToInternet) },
                                     watchProgressReporter: { _, _, _ in },
                                     progressStore: PlaybackProgressStore(defaults: try makeDefaults()))
        defer { player.stop() }
        player.session.surfacePresentation = .mini
        let original = player.session
        await player.load()
        await player.retry()
        XCTAssertFalse(player.session === original)
        XCTAssertEqual(player.session.surfacePresentation, .mini)
    }

    func testCompletedPresentationRetargetsNativeExitToMiniButKeepsCardEntry() throws {
        let defaults = try makeDefaults()
        let store = NowPlayingStore(defaults: defaults)
        defer { store.close() }
        store.open(route(), from: "entry-card")
        XCTAssertEqual(store.transitionSourceID, "entry-card")
        store.videoPageDidAppear()
        XCTAssertEqual(store.transitionSourceID, NowPlayingStore.miniPlayerTransitionSourceID)
        store.dismissVideoPage()
        let player = try XCTUnwrap(store.player)
        XCTAssertEqual(player.session.surfacePresentation, .page)
        store.finishDismissal()
        XCTAssertEqual(player.session.surfacePresentation, .mini)
        store.expandMiniPlayer()
        XCTAssertEqual(store.transitionSourceID, NowPlayingStore.miniPlayerTransitionSourceID)

        defaults.set(false, forKey: PlaybackWindowSettings.storageKey)
        store.applyMiniPlayerSetting()
        XCTAssertEqual(store.transitionSourceID, "entry-card", "Disabling the mini window restores a valid card destination")
    }

    func testOpenRelatedThenDismissNotifiesTheReplacementSessionAndPreservesZoomTarget() throws {
        let store = NowPlayingStore(defaults: try makeDefaults())
        defer { store.close() }
        store.open(route(), from: "entry-card")
        store.videoPageDidAppear()
        let oldPlayer = try XCTUnwrap(store.player)
        let related = VideoSummary(
            bvid: "BVMiniRelated-\(UUID().uuidString)", aid: 2, cid: 2,
            title: "相同画幅的下一条推荐视频", pic: "", desc: "", duration: 100, pubdate: 0,
            owner: VideoOwner(mid: 1, name: "测试", face: ""),
            stat: VideoStat(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0)
        )
        store.openRelated(related)
        let replacement = try XCTUnwrap(store.player)
        XCTAssertFalse(replacement === oldPlayer)
        XCTAssertEqual(store.route?.bvid, related.bvid)
        let mountedMini = OwnershipProbe(replacement.session.surfaceOwnership)
        replacement.session.surfaceOwnership.addObserver(mountedMini)

        store.dismissVideoPage()
        XCTAssertEqual(mountedMini.observed, [.page], "The page retains its pixels during the shrink animation")
        XCTAssertEqual(store.transitionSourceID, NowPlayingStore.miniPlayerTransitionSourceID)
        store.finishDismissal()
        XCTAssertEqual(mountedMini.observed, [.page, .mini], "The native completion actively wakes the replacement's already-mounted mini")
        XCTAssertTrue(store.player === replacement)
        oldPlayer.session.surfacePresentation = .mini
        XCTAssertEqual(mountedMini.observed, [.page, .mini])

        store.expandMiniPlayer()
        store.finishDismissal()
        XCTAssertEqual(mountedMini.observed, [.page, .mini, .page], "A late prior dismissal cannot steal the expanded video's surface")
        XCTAssertTrue(store.isExpanded)
        XCTAssertTrue(store.player === replacement)
    }

    func testFlickVelocityDeterminesDockingSideAndProjectsVerticalTravel() {
        let bounds = CGRect(x: 12, y: 59, width: 369, height: 640)
        let size = CGSize(width: 180, height: 110)
        let center = CGPoint(x: bounds.midX - 15, y: bounds.midY)
        let still = MiniPlayerLayout.restingAnchor(center: center, velocity: .zero, size: size, in: bounds)
        let rightFlick = MiniPlayerLayout.restingAnchor(center: center, velocity: CGPoint(x: 400, y: 300),
                                                       size: size, in: bounds)
        let leftFlick = MiniPlayerLayout.restingAnchor(center: CGPoint(x: bounds.midX + 15, y: center.y),
                                                      velocity: CGPoint(x: -400, y: -300), size: size, in: bounds)
        XCTAssertEqual(still.x, 0)
        XCTAssertEqual(rightFlick.x, 1, "A rightward flick can cross the midpoint even when released left of it")
        XCTAssertEqual(leftFlick.x, 0)
        XCTAssertGreaterThan(rightFlick.y, still.y)
        XCTAssertLessThan(leftFlick.y, still.y)
    }

    func testProjectedRestingAnchorClampsExtremeAndInvalidVelocities() {
        let bounds = CGRect(x: 12, y: 59, width: 369, height: 640)
        let size = CGSize(width: 180, height: 110)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        for velocity in [CGPoint(x: 100_000, y: 100_000), CGPoint(x: -100_000, y: -100_000),
                         CGPoint(x: CGFloat.nan, y: CGFloat.infinity)] {
            let anchor = MiniPlayerLayout.restingAnchor(center: center, velocity: velocity, size: size, in: bounds)
            XCTAssertTrue(anchor.x.isFinite && anchor.y.isFinite)
            XCTAssertTrue(anchor.x == 0 || anchor.x == 1)
            XCTAssertTrue((0...1).contains(anchor.y))
            let end = MiniPlayerLayout.center(anchor: anchor, size: size, in: bounds)
            XCTAssertGreaterThanOrEqual(end.x - size.width / 2, bounds.minX)
            XCTAssertLessThanOrEqual(end.x + size.width / 2, bounds.maxX)
            XCTAssertGreaterThanOrEqual(end.y - size.height / 2, bounds.minY)
            XCTAssertLessThanOrEqual(end.y + size.height / 2, bounds.maxY)
        }
    }

    func testSpringVelocityStaysFiniteAtZeroTinyAndExtremeDistances() {
        let start = CGPoint(x: 100, y: 100)
        let stopped = MiniPlayerLayout.springVelocity(CGPoint(x: 800, y: -800), from: start, to: start)
        XCTAssertEqual(stopped, .zero)
        let tiny = MiniPlayerLayout.springVelocity(CGPoint(x: 800, y: -800), from: start,
                                                   to: CGPoint(x: 100.5, y: 99.5))
        XCTAssertEqual(tiny, .zero)
        let invalid = MiniPlayerLayout.springVelocity(CGPoint(x: CGFloat.infinity, y: CGFloat.nan),
                                                      from: start, to: CGPoint(x: 200, y: 200))
        XCTAssertEqual(invalid, .zero)
        let extreme = MiniPlayerLayout.springVelocity(CGPoint(x: 1e12, y: -1e12), from: start,
                                                      to: CGPoint(x: 200, y: 200))
        XCTAssertTrue(extreme.dx.isFinite && extreme.dy.isFinite)
        XCTAssertLessThanOrEqual(abs(extreme.dx), 20)
        XCTAssertLessThanOrEqual(abs(extreme.dy), 20)
        XCTAssertGreaterThan(extreme.dx, 0)
        XCTAssertLessThan(extreme.dy, 0)
    }

}
