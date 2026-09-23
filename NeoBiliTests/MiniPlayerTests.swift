import XCTest
import UIKit
import SwiftUI
@testable import NeoBili

@MainActor
final class MiniPlayerTests: XCTestCase {
    func testTitleOnlyPlaybackKeepsVideoDisabledAcrossForegroundAndSessionChanges() {
        var state = PlayerVideoOutputState()
        XCTAssertTrue(state.isEnabled)
        state.presentation = .mini
        XCTAssertFalse(state.isEnabled)
        state.isBackgrounded = true
        state.isBackgrounded = false
        XCTAssertFalse(state.isEnabled, "Foregrounding a title-only player must not resume video decoding")
        state.isBackgrounded = true
        state.presentation = .page
        XCTAssertFalse(state.isEnabled)
        state.isBackgrounded = false
        XCTAssertTrue(state.isEnabled)

        let session = MPVPlayerSession(configuration: .init())
        defer { session.stop() }
        session.surfacePresentation = .mini
        XCTAssertFalse(session.viewController.videoOutput.isEnabled)
        session.surfacePresentation = .page
        XCTAssertTrue(session.viewController.videoOutput.isEnabled)
    }

    func testImmediateReturnKeepsEntryAnchorWithoutBlockingGestures() {
        let region = PlayerReturnGestureGuard.RegionView()
        region.verticalOnly = true
        let pan = UIPanGestureRecognizer()
        let gate = PlayerReturnGestureGuard.DelegateGate(region: region, recognizer: pan)
        XCTAssertTrue(gate.gestureRecognizerShouldBegin(pan))

        var presentation = MediaPresentationState()
        presentation.prepareSource("card")
        presentation.destination = .player
        XCTAssertEqual(presentation.source(for: "card"), .player)
        presentation.destination = nil
        presentation.completeEntrance(returningTo: NowPlayingStore.miniPlayerTransitionSourceID)
        XCTAssertEqual(presentation.source(for: "card"), .player,
                       "An immediate return must keep the entry anchor")
        // A cancelled return restores the native destination, then its source.
        presentation.destination = .player
        presentation.completeEntrance(returningTo: NowPlayingStore.miniPlayerTransitionSourceID)
        XCTAssertEqual(presentation.source(for: NowPlayingStore.miniPlayerTransitionSourceID), .player)
        XCTAssertEqual(presentation.source(for: "card"), .content("card"))
        XCTAssertTrue(gate.gestureRecognizerShouldBegin(pan))
    }

    func testLiveMiniPlayerReusesSessionAndCancelledDismissalRestoresPage() throws {
        let store = NowPlayingStore(defaults: try makeDefaults())
        defer { store.close() }
        store.openLiveAndMount(LiveRoom(roomID: 1, title: "直播测试", username: "主播"), from: "live-card")
        let live = try XCTUnwrap(store.livePlayer)
        let session = live.session
        XCTAssertNil(store.route)
        XCTAssertEqual(store.transitionSourceID, NowPlayingStore.miniPlayerTransitionSourceID)
        store.videoPageDidAppear()
        XCTAssertEqual(store.transitionSourceID, NowPlayingStore.miniPlayerTransitionSourceID)
        store.videoPageInteractionBegan()
        store.dismissVideoPage()
        XCTAssertEqual(session.surfacePresentation, .page)
        store.videoPageInteractionEnded(cancelled: true)
        store.finishDismissal()
        XCTAssertTrue(store.isExpanded)
        XCTAssertEqual(session.surfacePresentation, .page)
        store.dismissVideoPage()
        store.finishDismissal()
        XCTAssertEqual(session.surfacePresentation, .mini)
        XCTAssertTrue(store.isMiniPlayerPresented)
        store.expandMiniPlayer()
        XCTAssertTrue(store.livePlayer === live)
        XCTAssertTrue(store.activeSession === session)
        XCTAssertEqual(session.surfacePresentation, .page)
    }

    func testSwitchingBetweenLiveAndVideoReleasesPreviousMedia() throws {
        let store = NowPlayingStore()
        defer { store.close() }
        let room = LiveRoom(roomID: 1, title: "直播测试", username: "主播")
        store.openAndMount(route(), from: "video-card")
        store.openLiveAndMount(room, from: "live-card")
        XCTAssertNil(store.player)
        XCTAssertNil(store.route)
        XCTAssertNotNil(store.livePlayer)
        store.openAndMount(route(), from: "video-card")
        XCTAssertNil(store.livePlayer)
        XCTAssertNotNil(store.player)
        store.close()
        XCTAssertFalse(store.hasMedia)
    }

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
            store.openAndMount(route(), from: "card")
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
        store.openAndMount(route(), from: "card")
        store.videoPageInteractionBegan()
        XCTAssertNotNil(store.dismissalPlaybackPhase)
        store.videoPageInteractionEnded(cancelled: true)
        XCTAssertNil(store.dismissalPlaybackPhase)
        XCTAssertTrue(store.isExpanded)
        XCTAssertFalse(store.isMiniPlayerPresented)
    }

    func testRealTabAccessoryMountsBeforePresentingPage() async throws {
        let defaults = try makeDefaults()
        let store = NowPlayingStore(defaults: defaults)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: MiniAnchorFixture(store: store).defaultAppStorage(defaults))
        window.makeKeyAndVisible()
        defer { store.close(); window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(100))
        store.open(route(cid: nil), from: "fixture-card")
        XCTAssertNil(store.videoPresentation)
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(50))
            if store.videoPresentation != nil { break }
        }
        XCTAssertEqual(store.videoPresentation, .player, "A real accessory layout must release the pending presentation")
        XCTAssertNil(store.pendingPresentationID)
        XCTAssertEqual(store.matchedTransitionSource(for: "fixture-card"), .content("fixture-card"))
        XCTAssertEqual(store.matchedTransitionSource(for: NowPlayingStore.miniPlayerTransitionSourceID), .player)
    }

    func testMiniSourceMustMountBeforeExpansionAndRejectsStaleReadiness() throws {
        let store = NowPlayingStore(defaults: try makeDefaults())
        defer { store.close() }
        store.open(route(), from: "first-card")
        let first = try XCTUnwrap(store.pendingPresentationID)
        XCTAssertNil(store.videoPresentation)
        XCTAssertTrue(store.isMiniPlayerPresented)
        XCTAssertEqual(store.matchedTransitionSource(for: "first-card"), .content("first-card"))
        XCTAssertEqual(store.matchedTransitionSource(for: NowPlayingStore.miniPlayerTransitionSourceID), .player)
        store.open(route(), from: "second-card")
        let second = try XCTUnwrap(store.pendingPresentationID)
        store.miniPlayerSourceDidLayout(request: first)
        XCTAssertNil(store.videoPresentation)
        store.finishDismissal()
        XCTAssertNotNil(store.player)
        store.miniPlayerSourceDidLayout(request: second)
        XCTAssertEqual(store.videoPresentation, .player)
        store.dismissVideoPage()
        store.finishDismissal()
        XCTAssertTrue(store.isMiniPlayerPresented)
        store.open(route(), from: "third-card")
        let cancelled = try XCTUnwrap(store.pendingPresentationID)
        store.close()
        store.miniPlayerSourceDidLayout(request: cancelled)
        XCTAssertNil(store.videoPresentation)
    }

    func testMiniPlayerPreferenceDefaultsOnAndRespectsChanges() throws {
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
        store.openAndMount(video, from: "test-card")
        let player = try XCTUnwrap(store.player)
        let session = player.session
        XCTAssertEqual(session.surfacePresentation, .page)
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

        store.finishDismissal()
        XCTAssertFalse(store.isVideoPageDismissalInProgress)
        XCTAssertTrue(store.isMiniPlayerPresented)
        XCTAssertTrue(store.player === player)
        XCTAssertEqual(player.duration, 300)
        XCTAssertTrue(player.hasRenderedFirstFrame)
        XCTAssertEqual(session.surfacePresentation, .mini)

        store.expandMiniPlayer()
        XCTAssertTrue(store.isExpanded)
        XCTAssertFalse(store.isMiniPlayerPresented)
        XCTAssertEqual(store.transitionSourceID, NowPlayingStore.miniPlayerTransitionSourceID)
        XCTAssertEqual(session.surfacePresentation, .page)
        XCTAssertTrue(store.player === player)
        XCTAssertTrue(player.session === session)
        XCTAssertEqual(player.currentTime, 37.25)
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(store.route, video)
        XCTAssertEqual(store.section, .comments)
        XCTAssertTrue(store.isDescriptionExpanded)
    }

    func testDisabledMiniPlayerStopsAfterDismissalCompletes() throws {
        let defaults = try makeDefaults()
        defaults.set(false, forKey: PlaybackWindowSettings.storageKey)
        let store = NowPlayingStore(defaults: defaults)
        defer { store.close() }
        store.openAndMount(route(), from: "test-card")
        store.videoPageDidAppear()
        XCTAssertEqual(store.matchedTransitionSource(for: "test-card"), .player)
        let player = try XCTUnwrap(store.player)
        player.session.onEvent?(.playing(true))
        store.dismissVideoPage()
        XCTAssertTrue(store.player === player)
        XCTAssertFalse(store.isMiniPlayerPresented)
        store.finishDismissal()
        XCTAssertNil(store.route)
        XCTAssertNil(store.player)
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(store.isMiniPlayerPresented)
    }

    func testReopeningDuringDismissalReusesPlayerAndIgnoresOldCompletion() throws {
        let defaults = try makeDefaults()
        defaults.set(false, forKey: PlaybackWindowSettings.storageKey)
        let store = NowPlayingStore(defaults: defaults)
        defer { store.close() }
        let video = route()
        store.openAndMount(video, from: "test-card")
        let oldPlayer = try XCTUnwrap(store.player)
        store.dismissVideoPage()
        store.openAndMount(video, from: "test-card")
        let newPlayer = try XCTUnwrap(store.player)
        store.finishDismissal()
        XCTAssertTrue(newPlayer === oldPlayer)
        XCTAssertTrue(store.player === newPlayer)
        XCTAssertEqual(store.route, video)
        XCTAssertTrue(store.isExpanded)
        XCTAssertFalse(store.isMiniPlayerPresented)
        XCTAssertNil(store.dismissalPlaybackPhase)
    }

    func testDisablingMiniPlayerClosesExistingMiniPlayer() throws {
        let defaults = try makeDefaults()
        let store = NowPlayingStore(defaults: defaults)
        defer { store.close() }
        store.openAndMount(route(), from: "test-card")
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
        store.openAndMount(route(), from: "test-card")
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
        store.openAndMount(video, from: "first-card")
        let player = try XCTUnwrap(store.player)
        store.dismissVideoPage()
        store.openAndMount(video, from: "second-card")
        store.finishDismissal()

        XCTAssertTrue(store.isExpanded)
        XCTAssertFalse(store.isMiniPlayerPresented)
        XCTAssertTrue(store.player === player)
        XCTAssertEqual(store.route, video)
        XCTAssertEqual(store.transitionSourceID, NowPlayingStore.miniPlayerTransitionSourceID)
        XCTAssertEqual(player.session.surfacePresentation, .page)
    }

    func testLateDismissalCannotCloseANewVideo() throws {
        let store = NowPlayingStore(defaults: try makeDefaults())
        defer { store.close() }
        store.openAndMount(route(), from: "first-card")
        let oldPlayer = try XCTUnwrap(store.player)
        oldPlayer.session.onEvent?(.playing(true))
        store.dismissVideoPage()
        let next = route(cid: 2)
        store.openAndMount(next, from: "next-card")
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
        store.openAndMount(video, from: "dynamic-card")
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

    func testPlayerCreatedAfterCIDBecomesAvailableInheritsMiniOwnership() throws {
        let store = NowPlayingStore(defaults: try makeDefaults())
        defer { store.close() }
        store.openAndMount(route(cid: nil), from: "dynamic-card")
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
        store.openAndMount(route(cid: nil), from: "dynamic-card")
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

    func testCompletedPresentationKeepsStableEntryWhileMiniExpansionUsesMini() throws {
        let defaults = try makeDefaults()
        let store = NowPlayingStore(defaults: defaults)
        defer { store.close() }
        store.openAndMount(route(), from: "entry-card")
        XCTAssertEqual(store.videoPresentation, .player)
        XCTAssertEqual(store.matchedTransitionSource(for: "entry-card"), .content("entry-card"))
        store.applyMiniPlayerSetting()
        XCTAssertEqual(store.matchedTransitionSource(for: "entry-card"), .content("entry-card"))
        store.videoPageDidAppear()
        XCTAssertEqual(store.transitionSourceID, NowPlayingStore.miniPlayerTransitionSourceID)
        XCTAssertEqual(store.matchedTransitionSource(for: "entry-card"), .content("entry-card"))
        XCTAssertEqual(store.matchedTransitionSource(for: NowPlayingStore.miniPlayerTransitionSourceID), .player)
        store.dismissVideoPage()
        XCTAssertNil(store.videoPresentation)
        let player = try XCTUnwrap(store.player)
        XCTAssertEqual(player.session.surfacePresentation, .page)
        store.finishDismissal()
        XCTAssertEqual(player.session.surfacePresentation, .mini)
        store.expandMiniPlayer()
        XCTAssertEqual(store.transitionSourceID, NowPlayingStore.miniPlayerTransitionSourceID)

        defaults.set(false, forKey: PlaybackWindowSettings.storageKey)
        store.applyMiniPlayerSetting()
        XCTAssertEqual(store.transitionSourceID, NowPlayingStore.miniPlayerTransitionSourceID, "Legacy preferences must not change the persistent player destination")
    }

    func testOpenRelatedThenDismissNotifiesTheReplacementSessionAndPreservesZoomTarget() throws {
        let store = NowPlayingStore(defaults: try makeDefaults())
        defer { store.close() }
        store.openAndMount(route(), from: "entry-card")
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

}

@MainActor private extension NowPlayingStore {
    func openAndMount(_ route: VideoDetailRoute, from source: String) {
        open(route, from: source)
        if let request = pendingPresentationID { miniPlayerSourceDidLayout(request: request) }
    }
    func openLiveAndMount(_ room: LiveRoom, from source: String) {
        openLive(room, from: source)
        if let request = pendingPresentationID { miniPlayerSourceDidLayout(request: request) }
    }
}

private struct MiniAnchorFixture: View {
    let store: NowPlayingStore
    @Namespace private var transition
    var body: some View {
        TabView {
            Color.clear.tabItem { Label("测试", systemImage: "play") }
        }
        .tabMiniPlayerHost(transitionNamespace: transition)
        .environment(store)
    }
}
