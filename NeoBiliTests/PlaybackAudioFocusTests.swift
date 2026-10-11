import XCTest
@testable import NeoBili

@MainActor
final class PlaybackAudioFocusTests: XCTestCase {
    @MainActor private final class Probe {
        var configured = 0
        var activations: [PlaybackAudioSession.Completion] = []
        var deactivations: [PlaybackAudioSession.Completion] = []
        lazy var session = PlaybackAudioSession(endpoint: .init(
            configure: { [weak self] in self?.configured += 1 },
            activate: { [weak self] in self?.activations.append($0) },
            deactivate: { [weak self] in self?.deactivations.append($0) }
        ))
    }

    func testConstructionAndSilentPreviewNeverRequestAudioFocus() async throws {
        let probe = Probe()
        let audible = MPVPlayerSession(configuration: .fastStart, audioSession: probe.session)
        audible.refreshAudioFocusIfNeeded()
        var configuration = VideoPlaybackConfiguration.fastStart
        configuration.silentPreview = true
        let preview = MPVPlayerSession(configuration: configuration, audioSession: probe.session)
        let source = PlaybackSource(video: .init(primary: URL(string: "https://example.invalid/video")!, backups: []), audio: nil, duration: 10)
        try await preview.open(source: source)
        preview.play()
        preview.refreshAudioFocusIfNeeded()
        preview.stop()
        audible.stop()
        XCTAssertEqual(probe.configured, 0)
        XCTAssertTrue(probe.activations.isEmpty)
        XCTAssertTrue(probe.deactivations.isEmpty)
    }

    func testLastOwnerReleasesFocusAndDuplicateRequestsAreIdempotent() {
        let probe = Probe(), first = UUID(), second = UUID()
        probe.session.acquire(first)
        probe.session.acquire(first)
        probe.session.acquire(second)
        XCTAssertEqual(probe.activations.count, 1)
        probe.activations[0](true)
        probe.session.release(first)
        probe.session.release(first)
        XCTAssertTrue(probe.deactivations.isEmpty)
        probe.session.release(second)
        XCTAssertEqual(probe.deactivations.count, 1)
        probe.deactivations[0](true)
    }

    func testPauseBeforeActivationCompletesReleasesLateAudioFocus() {
        let probe = Probe(), owner = UUID()
        probe.session.acquire(owner)
        probe.session.release(owner)
        XCTAssertTrue(probe.deactivations.isEmpty)
        probe.activations[0](true)
        XCTAssertEqual(probe.deactivations.count, 1)
        probe.deactivations[0](true)
    }

    func testResumeDuringDeactivationWaitsThenReactivates() {
        let probe = Probe(), owner = UUID()
        probe.session.acquire(owner)
        probe.activations[0](true)
        probe.session.release(owner)
        probe.session.acquire(owner)
        XCTAssertEqual(probe.activations.count, 1)
        probe.deactivations[0](true)
        XCTAssertEqual(probe.activations.count, 2)
        probe.activations[1](true)
        probe.session.release(owner)
        probe.deactivations[1](true)
    }

    func testFailedActivationRetriesOnlyOnNewPlaybackRequest() {
        let probe = Probe(), owner = UUID()
        probe.session.acquire(owner)
        probe.activations[0](false)
        XCTAssertEqual(probe.activations.count, 1)
        probe.session.acquire(owner)
        XCTAssertEqual(probe.activations.count, 2)
        probe.activations[1](true)
        probe.session.release(owner)
        probe.deactivations[0](true)
    }

    func testAudiblePlayPauseAndStopOwnAudioFocus() async {
        let probe = Probe()
        let player = MPVPlayerSession(configuration: .fastStart, audioSession: probe.session)
        player.play()
        XCTAssertEqual(probe.activations.count, 1)
        probe.activations[0](true)
        player.pause()
        XCTAssertEqual(probe.deactivations.count, 1)
        probe.deactivations[0](true)
        player.refreshAudioFocusIfNeeded()
        XCTAssertEqual(probe.activations.count, 1)
        player.play()
        probe.activations[1](true)
        player.stop()
        for _ in 0..<100 where probe.deactivations.count < 2 { await Task.yield() }
        XCTAssertEqual(probe.deactivations.count, 2)
        guard probe.deactivations.count == 2 else { return }
        probe.deactivations[1](true)
        player.play()
        XCTAssertEqual(probe.activations.count, 2)
    }

    func testNativeEOFAndFailureReleaseAudioBeforeForwardingEvent() {
        let probe = Probe()
        let player = MPVPlayerSession(configuration: .fastStart, audioSession: probe.session)
        var received = 0
        player.onEvent = { _ in received += 1 }
        player.play()
        probe.activations[0](true)
        player.viewController.onEvent?(.ended)
        XCTAssertEqual(probe.deactivations.count, 1)
        XCTAssertEqual(received, 1)
        probe.deactivations[0](true)
        player.play()
        probe.activations[1](true)
        player.viewController.onEvent?(.error("failure"))
        XCTAssertEqual(probe.deactivations.count, 2)
        XCTAssertEqual(received, 2)
        probe.deactivations[1](true)
        player.stop()
    }

    func testLatePauseEventDoesNotEraseNewPlaybackIntent() {
        let probe = Probe()
        let player = MPVPlayerSession(configuration: .fastStart, audioSession: probe.session)
        player.onEvent = { _ in }
        player.play()
        probe.activations[0](true)
        player.viewController.onEvent?(.playing(false))
        XCTAssertEqual(probe.deactivations.count, 1)
        player.viewController.onEvent?(.playing(true))
        probe.deactivations[0](true)
        XCTAssertEqual(probe.activations.count, 2)
        probe.activations[1](true)
        player.pause()
        probe.deactivations[1](true)
        player.viewController.onEvent?(.playing(true))
        XCTAssertEqual(probe.activations.count, 2, "A late playing event after explicit pause must not steal audio focus")
        player.stop()
    }

    func testDeactivationHasBoundedRetryAndConfirmedStopCanRetryAgain() {
        let probe = Probe(), owner = UUID()
        probe.session.acquire(owner)
        probe.activations[0](true)
        probe.session.release(owner)
        probe.deactivations[0](false)
        XCTAssertEqual(probe.deactivations.count, 2)
        probe.deactivations[1](false)
        XCTAssertEqual(probe.deactivations.count, 2, "No unbounded retry or polling")
        probe.session.release(owner)
        XCTAssertEqual(probe.deactivations.count, 3)
        probe.deactivations[2](true)
        probe.session.acquire(owner)
        XCTAssertEqual(probe.activations.count, 2)
        probe.activations[1](true)
        probe.session.release(owner)
        probe.deactivations[3](true)
    }
}
