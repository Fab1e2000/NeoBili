import XCTest
@testable import NeoBili

@MainActor
final class PlayerQualityTests: XCTestCase {
    func testDeclared4KIsNotMistakenForAnAlreadyAuthorizedStream() throws {
        let payload = try Self.payload(quality: 80)
        XCTAssertEqual(payload.declaredVideoQualities, [120, 80, 64])
        XCTAssertTrue(payload.hasVideoStream(quality: 80))
        XCTAssertFalse(payload.hasVideoStream(quality: 120))
        XCTAssertFalse(payload.declaredVideoQualities.contains(127))
        XCTAssertEqual(payload.supportFormats?.first?.needsVIP, true)
        XCTAssertEqual(payload.supportFormats?.last?.needsLogin, true)
    }

    func testLoggedInPlaybackDoesNotRequestTheAnonymousTrial() {
        let loggedIn = BiliAPI.playbackContextParams(isLoggedIn: true)
        XCTAssertNil(loggedIn["try_look"])
        XCTAssertNil(loggedIn["dm_img_str"])
        XCTAssertNil(loggedIn["dm_cover_img_str"])
        XCTAssertEqual(BiliAPI.playbackContextParams(isLoggedIn: false)["try_look"], "1")
    }

    func testMissing4KFetchesExactQNAndKeepsPausedProgressAndSurfaceOwner() async throws {
        let low = try Self.payload(quality: 80), high = try Self.payload(quality: 120)
        let requests = QualityRequestProbe(result: high)
        var opened: [(PlaybackSource, Double)] = []
        let player = try makePlayer(payload: low, loader: { _, _, qn in await requests.load(qn) },
                                    opener: { _, source, position in opened.append((source, position)) })
        defer { player.stop() }
        await player.load()
        ready(player, position: 37)
        player.session.onEvent?(.decodedVideoSize(width: 1920, height: 1080))
        player.pause()
        let originalSession = player.session
        let originalCallback = originalSession.onEvent
        originalSession.surfacePresentation = .mini

        let message = await player.selectQuality(video: 120)
        XCTAssertNil(message)
        let qualities = await requests.qualities
        XCTAssertEqual(qualities, [120])
        XCTAssertEqual(opened.last?.0.video.primary.path, "/q120.m4s")
        XCTAssertEqual(opened.last?.1, 37)
        XCTAssertEqual(player.currentTime, 37)
        XCTAssertEqual(player.selectedVideoQuality, 120)
        XCTAssertEqual(player.selectedVideoWidth, 3840)
        XCTAssertEqual(player.selectedVideoHeight, 2160)
        XCTAssertNil(player.decodedVideoWidth, "Track metadata must not be reported as decoded dimensions")
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(originalSession === player.session)
        XCTAssertEqual(player.session.surfacePresentation, .mini)
        originalCallback?(.position(0))
        originalCallback?(.error("old stream"))
        originalCallback?(.decodedVideoSize(width: 1920, height: 1080))
        XCTAssertNil(player.decodedVideoWidth)
        player.session.onEvent?(.playing(true))
        XCTAssertFalse(player.isPlaying, "New engine autoplay must not override paused intent")
        player.session.onEvent?(.firstFrame)
        player.session.onEvent?(.decodedVideoSize(width: 3840, height: 2160))
        XCTAssertEqual(player.decodedVideoWidth, 3840)
        XCTAssertEqual(player.decodedVideoHeight, 2160)
        XCTAssertFalse(player.isPlaying)
        XCTAssertNil(player.errorMessage)
        XCTAssertEqual(player.currentTime, 37)
        XCTAssertTrue(player.availableVideoQualities.contains(80), "Previous declared formats remain selectable")
    }

    func testServerDowngradeKeepsOldPlaybackAndReportsPermission() async throws {
        let low = try Self.payload(quality: 80)
        var opens = 0
        let player = try makePlayer(payload: low, loader: { _, _, _ in low }, opener: { _, _, _ in opens += 1 })
        defer { player.stop() }
        await player.load()
        ready(player, position: 42)
        let original = player.session
        let message = await player.selectQuality(video: 120)
        XCTAssertTrue(message?.contains("大会员") == true)
        XCTAssertTrue(original === player.session)
        XCTAssertEqual(opens, 1)
        XCTAssertEqual(player.selectedVideoQuality, 80)
        XCTAssertEqual(player.configuration.quality, 80)
        XCTAssertEqual(player.currentTime, 42)
        XCTAssertTrue(player.isPlaying)
        XCTAssertFalse(player.isLoading)
        XCTAssertFalse(player.isSwitchingQuality)
    }

    func testPauseDuringQualityFetchKeepsLatestPositionAndRejectsDoubleSelection() async throws {
        let low = try Self.payload(quality: 80), high = try Self.payload(quality: 120)
        let requests = QualityRequestProbe(result: high, holds: true)
        var positions: [Double] = []
        let player = try makePlayer(payload: low, loader: { _, _, qn in await requests.load(qn) },
                                    opener: { _, _, position in positions.append(position) })
        defer { player.stop() }
        await player.load()
        ready(player, position: 12)
        let change = Task { await player.selectQuality(video: 120) }
        try await waitUntil { await requests.qualities.count == 1 }
        let duplicate = await player.selectQuality(video: 120)
        XCTAssertNil(duplicate)
        player.session.onEvent?(.position(20))
        player.pause()
        await requests.release()
        _ = await change.value
        XCTAssertEqual(positions, [0, 20])
        XCTAssertFalse(player.isPlaying)
        let qualities = await requests.qualities
        XCTAssertEqual(qualities, [120])
    }

    func testStopRejectsLateQualityResponseWithoutOpeningOrError() async throws {
        let requests = QualityRequestProbe(result: try Self.payload(quality: 120), holds: true)
        var opens = 0
        let player = try makePlayer(payload: Self.payload(quality: 80), loader: { _, _, qn in await requests.load(qn) },
                                    opener: { _, _, _ in opens += 1 })
        await player.load()
        ready(player, position: 18)
        let change = Task { await player.selectQuality(video: 120) }
        try await waitUntil { await requests.qualities.count == 1 }
        player.stop()
        await requests.release()
        let message = await change.value
        XCTAssertNil(message)
        XCTAssertEqual(opens, 1)
        XCTAssertEqual(player.selectedVideoQuality, 80)
        XCTAssertFalse(player.isLoading)
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(player.isSwitchingQuality)
        XCTAssertNil(player.errorMessage)
    }

    func testFetchFailureLeavesExistingPlaybackUntouched() async throws {
        let player = try makePlayer(payload: Self.payload(quality: 80), loader: { _, _, _ in throw URLError(.notConnectedToInternet) })
        defer { player.stop() }
        await player.load()
        ready(player, position: 23)
        let original = player.session
        let message = await player.selectQuality(video: 120)
        XCTAssertNotNil(message)
        XCTAssertTrue(original === player.session)
        XCTAssertEqual(player.currentTime, 23)
        XCTAssertTrue(player.isPlaying)
        XCTAssertFalse(player.isSwitchingQuality)
        XCTAssertNil(player.errorMessage)
    }

    func testLateQualityOpenFailureCannotOverwriteRecoveredBackup() async throws {
        let low = try Self.payload(quality: 80), high = try Self.payload(quality: 120, backup: true)
        var opens = 0
        var heldOpen: CheckedContinuation<Void, Error>?
        let player = try makePlayer(payload: low, loader: { _, _, _ in high }, opener: { session, _, _ in
            opens += 1
            if opens == 2 { try await withCheckedThrowingContinuation { heldOpen = $0 } }
            else if opens == 3 { session.onEvent?(.firstFrame) }
        })
        defer { player.stop() }
        await player.load()
        ready(player, position: 28)
        let change = Task { await player.selectQuality(video: 120) }
        for _ in 0..<100 where heldOpen == nil { await Task.yield() }
        XCTAssertNotNil(heldOpen)
        player.session.onEvent?(.error("primary CDN failed"))
        for _ in 0..<100 where opens < 3 { await Task.yield() }
        XCTAssertEqual(opens, 3)
        let recovered = player.session
        heldOpen?.resume(throwing: URLError(.cannotConnectToHost))
        _ = await change.value
        XCTAssertTrue(recovered === player.session)
        XCTAssertTrue(player.hasRenderedFirstFrame)
        XCTAssertNil(player.errorMessage)
        XCTAssertFalse(player.isLoading)
        XCTAssertEqual(player.selectedVideoQuality, 120)
    }

    func testStopWhileOpeningQualityRejectsLateCompletion() async throws {
        let high = try Self.payload(quality: 120)
        var opens = 0
        var heldOpen: CheckedContinuation<Void, Error>?
        let player = try makePlayer(payload: Self.payload(quality: 80), loader: { _, _, _ in high }, opener: { _, _, _ in
            opens += 1
            if opens == 2 { try await withCheckedThrowingContinuation { heldOpen = $0 } }
        })
        await player.load()
        ready(player, position: 18)
        let change = Task { await player.selectQuality(video: 120) }
        for _ in 0..<100 where heldOpen == nil { await Task.yield() }
        XCTAssertNotNil(heldOpen)
        player.stop()
        heldOpen?.resume(throwing: URLError(.cancelled))
        _ = await change.value
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(player.isLoading)
        XCTAssertNil(player.errorMessage)
    }

    func testAudioSwitchUsesExistingTracksWithoutVideoRequest() async throws {
        let requests = QualityRequestProbe(result: try Self.payload(quality: 120))
        let player = try makePlayer(payload: Self.payload(quality: 80), loader: { _, _, qn in await requests.load(qn) })
        defer { player.stop() }
        await player.load()
        ready(player, position: 5)
        _ = await player.selectQuality(audio: 30216)
        let qualities = await requests.qualities
        XCTAssertTrue(qualities.isEmpty)
        XCTAssertEqual(player.selectedAudioQuality, 30216)
        XCTAssertEqual(player.selectedVideoQuality, 80)
        XCTAssertEqual(player.currentTime, 5)
    }

    func testCurrentQualityReflectsActualStreamWhenPreferenceIsHigher() async throws {
        let low = try Self.payload(quality: 80)
        var configuration = VideoPlaybackConfiguration.fastStart
        configuration.quality = 120
        let player = PlayerViewModel(bvid: "BVQualityTest", cid: 1, configuration: configuration,
            playbackURLLoader: { _, _ in low }, watchProgressReporter: { _, _, _ in },
            progressStore: try makeStore(), sourceOpener: { _, _, _ in })
        defer { player.stop() }
        await player.load()
        XCTAssertEqual(player.selectedVideoQuality, 80)
        XCTAssertTrue(player.availableVideoQualities.contains(120))
    }

    private func makePlayer(payload: PlayURLData,
                            loader: @escaping QualityPlaybackURLLoader,
                            opener: @escaping PlaybackSourceOpener = { _, _, _ in }) throws -> PlayerViewModel {
        var configuration = VideoPlaybackConfiguration.fastStart
        configuration.quality = 80
        configuration.audioQuality = 30280
        return PlayerViewModel(bvid: "BVQualityTest", cid: 1, configuration: configuration,
            playbackURLLoader: { _, _ in payload }, qualityPlaybackURLLoader: loader,
            watchProgressReporter: { _, _, _ in }, progressStore: try makeStore(), sourceOpener: opener)
    }

    private func makeStore() throws -> PlaybackProgressStore {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "neobili.quality.tests.\(UUID())"))
        return PlaybackProgressStore(defaults: defaults)
    }

    private func ready(_ player: PlayerViewModel, position: Double) {
        player.session.onEvent?(.firstFrame)
        player.session.onEvent?(.playing(true))
        player.session.onEvent?(.position(position))
    }

    private func waitUntil(_ condition: @Sendable () async -> Bool) async throws {
        for _ in 0..<400 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw URLError(.timedOut)
    }

    private static func payload(quality: Int, backup: Bool = false) throws -> PlayURLData {
        let backupJSON = backup ? #", "backup_url":["https://backup.example.invalid/q120.m4s"]"# : ""
        return try JSONDecoder().decode(PlayURLData.self, from: Data("""
        {"quality":\(quality),"accept_quality":[120,80,64],
         "support_formats":[{"quality":120,"new_description":"4K 超清","need_vip":true},
                            {"quality":80,"new_description":"1080P 高清","need_login":1}],
         "dash":{"duration":300,"video":[{"id":\(quality),"base_url":"https://cdn.example.invalid/q\(quality).m4s"\(backupJSON),
         "bandwidth":10000000,"mime_type":"video/mp4","codecs":"hvc1.1.6.L150.90","width":\(quality == 120 ? 3840 : 1920),"height":\(quality == 120 ? 2160 : 1080)}],
         "audio":[{"id":30280,"base_url":"https://cdn.example.invalid/audio.m4s","bandwidth":192000,"mime_type":"audio/mp4","codecs":"mp4a.40.2"},
                  {"id":30216,"base_url":"https://cdn.example.invalid/audio-low.m4s","bandwidth":64000,"mime_type":"audio/mp4","codecs":"mp4a.40.2"}]}}
        """.utf8))
    }
}

private actor QualityRequestProbe {
    let result: PlayURLData
    let holds: Bool
    private(set) var qualities: [Int] = []
    private var continuation: CheckedContinuation<Void, Never>?
    init(result: PlayURLData, holds: Bool = false) { self.result = result; self.holds = holds }
    func load(_ quality: Int) async -> PlayURLData {
        qualities.append(quality)
        if holds { await withCheckedContinuation { continuation = $0 } }
        return result
    }
    func release() { continuation?.resume(); continuation = nil }
}
