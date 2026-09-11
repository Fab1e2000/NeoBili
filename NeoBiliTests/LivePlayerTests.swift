import MediaPlayer
import XCTest
@testable import NeoBili

/// Sources and responses are injected: these tests never mount or open an mpv surface.
@MainActor
final class LivePlayerTests: XCTestCase {
    func testPlaybackStartsBeforeSlowRoomMetadataAndReusesPreparedEngine() async throws {
        let metadata = LivePlayerResponseGate<LiveRoom>()
        defer { Task { await metadata.cancelAll() } }
        let payload = playback()
        let model = LivePlayerModel(room: room(), roomLoader: { _ in try await metadata.load() },
                                    playbackLoader: { _, _ in payload },
                                    sourceOpener: { session, _, _ in session.onEvent?(.firstFrame) },
                                    publishesSystemMedia: false)
        defer { model.stop() }
        let preparedEngine = model.session
        await model.load()
        try await waitUntil { await metadata.hasPending(1) }

        XCTAssertTrue(model.hasRenderedFirstFrame, "A slow room header must not block playback")
        XCTAssertTrue(model.isPlaying)
        XCTAssertTrue(model.session === preparedEngine, "Keep the renderer already mounted by LiveRoomView")
        await metadata.fail(1)
        await Task.yield()
        XCTAssertNil(model.errorMessage, "A failed metadata request must not close a playable stream")
        XCTAssertTrue(model.isPlaying)
    }

    func testLiveAddressStatusTakesPrecedenceOverStaleOfflineMetadata() async throws {
        let offline = room(status: 0)
        let payload = playback()
        let model = LivePlayerModel(room: room(), roomLoader: { _ in offline },
                                    playbackLoader: { _, _ in payload },
                                    sourceOpener: { session, _, _ in session.onEvent?(.firstFrame) },
                                    publishesSystemMedia: false)
        defer { model.stop() }
        await model.load()
        try await waitUntil { model.room == offline }
        XCTAssertFalse(model.isOffline)
        XCTAssertTrue(model.isPlaying, "The live-status of the actual stream response governs playback")
    }

    func testStartupTimeoutCoversPendingOpenerAndRejectsItsLateFailure() async throws {
        let gate = LivePlayerResponseGate<Bool>()
        defer { Task { await gate.cancelAll() } }
        let info = room()
        let payload = playback(candidateCount: 2)
        var opened = 0
        let model = LivePlayerModel(room: info, roomLoader: { _ in info }, playbackLoader: { _, _ in payload },
                                    sourceOpener: { session, _, _ in
            opened += 1
            if opened == 1 { _ = try await gate.load() }
            else { session.onEvent?(.firstFrame) }
        }, publishesSystemMedia: false, startupTimeout: .milliseconds(40))
        defer { model.stop() }
        let request = Task { await model.load() }
        try await waitUntil { opened == 2 && model.hasRenderedFirstFrame }
        let workingEngine = model.session
        await gate.fail(1)
        await request.value

        XCTAssertTrue(model.session === workingEngine)
        XCTAssertTrue(model.isPlaying)
        XCTAssertNil(model.errorMessage)
    }

    func testLiveStartupKeepsDirectFLVAndHLSFallbackWithinFourCandidates() {
        let hls = (0..<5).map { Self.candidate(index: $0) }
        let flv = LiveStreamCandidate(url: URL(string: "https://stream.example.invalid/live.flv?token=preserved")!,
                                      protocolName: "http_stream", formatName: "flv", codecName: "avc", quality: 10000)
        let candidates = LiveStreamStartupPolicy.candidates(from: hls + [flv, flv])
        XCTAssertEqual(candidates.count, 4)
        XCTAssertEqual(candidates[0], flv)
        XCTAssertEqual(candidates[1], hls[0])
        XCTAssertEqual(Set(candidates.map(\.url)).count, candidates.count)
        XCTAssertEqual(candidates[0].url.query, "token=preserved")
    }

    func testLiveBufferBudgetDoesNotChangeVODOptions() {
        let live = VideoPlaybackConfiguration.live(roomID: 17)
        XCTAssertEqual(live.maxBufferBytes, 8 * 1024 * 1024)
        XCTAssertEqual(live.maxBackBufferBytes, 0)
        XCTAssertEqual(live.initialBufferSeconds, 1)
        XCTAssertEqual(VideoPlaybackConfiguration.fastStart.maxBufferBytes, 32 * 1024 * 1024)
        XCTAssertEqual(VideoPlaybackConfiguration.fastStart.initialBufferSeconds, 3)
    }

    func testOfflinePlaybackStatusDoesNotOpenAStream() async throws {
        let offline = room(status: 0)
        let playback = playback(status: 0)
        var opens = 0
        let model = LivePlayerModel(room: room(), roomLoader: { _ in offline }, playbackLoader: { _, _ in
            return playback
        }, sourceOpener: { _, _, _ in opens += 1 }, publishesSystemMedia: false)
        defer { model.stop() }
        await model.load()

        try await waitUntil { model.room == offline }
        XCTAssertEqual(model.room, offline)
        XCTAssertTrue(model.isOffline)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.isPlaying)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(opens, 0)
    }

    func testRoomGoingOfflineBetweenInfoAndPlaybackDoesNotOpenAStream() async {
        let model = makeModel(playback: playback(status: 0), opener: { _, _, _ in
            XCTFail("An offline play URL response must not start playback")
        })
        defer { model.stop() }
        await model.load()
        XCTAssertTrue(model.isOffline)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
    }

    func testStopRejectsLateRoomAndPlaybackResponses() async throws {
        let roomGate = LivePlayerResponseGate<LiveRoom>()
        let playbackGate = LivePlayerResponseGate<LivePlayback>()
        defer { Task { await roomGate.cancelAll(); await playbackGate.cancelAll() } }
        let seed = room()
        let model = LivePlayerModel(room: seed, roomLoader: { _ in try await roomGate.load() },
                                    playbackLoader: { _, _ in try await playbackGate.load() },
                                    sourceOpener: { _, _, _ in XCTFail("A stopped room cannot open a stream") },
                                    publishesSystemMedia: false)
        defer { model.stop() }
        let request = Task { await model.load() }
        try await waitUntil { await roomGate.hasPending(1) }
        try await waitUntil { await playbackGate.hasPending(1) }
        model.stop()
        await roomGate.resolve(1, value: room(title: "迟到的房间"))
        await playbackGate.resolve(1, value: playback())
        await request.value

        XCTAssertEqual(model.room, seed)
        XCTAssertFalse(model.isPlaying)
        XCTAssertFalse(model.hasRenderedFirstFrame)
        XCTAssertNil(model.session.onEvent)
        XCTAssertNil(model.errorMessage)
        await model.load()
        let count = await roomGate.requestCount
        XCTAssertEqual(count, 1, "stop is terminal for this model")
    }

    func testStopRejectsLatePlaybackResponseAndOldEngineEvents() async throws {
        let gate = LivePlayerResponseGate<LivePlayback>()
        defer { Task { await gate.cancelAll() } }
        let info = room()
        let model = LivePlayerModel(room: info, roomLoader: { _ in info },
                                    playbackLoader: { _, _ in try await gate.load() },
                                    sourceOpener: { _, _, _ in XCTFail("Closed playback must not open a stream") },
                                    publishesSystemMedia: false)
        defer { model.stop() }
        let request = Task { await model.load() }
        try await waitUntil { await gate.hasPending(1) }
        model.stop()
        await gate.resolve(1, value: playback())
        await request.value
        model.receive(.firstFrame)
        model.receive(.error("迟到的错误"))
        model.receive(.displayAspectRatio(9.0 / 16))

        XCTAssertTrue(model.qualities.isEmpty)
        XCTAssertFalse(model.isPlaying)
        XCTAssertFalse(model.hasRenderedFirstFrame)
        XCTAssertNil(model.displayAspectRatio)
        XCTAssertNil(model.errorMessage)
    }

    func testNewLoadRejectsSupersededRoomResponse() async throws {
        let gate = LivePlayerResponseGate<LiveRoom>()
        defer { Task { await gate.cancelAll() } }
        let payload = playback()
        var opens = 0
        let model = LivePlayerModel(room: room(), roomLoader: { _ in try await gate.load() },
                                    playbackLoader: { _, _ in payload },
                                    sourceOpener: { session, _, _ in opens += 1; session.onEvent?(.firstFrame) },
                                    publishesSystemMedia: false)
        defer { model.stop() }
        let old = Task { await model.load() }
        try await waitUntil { await gate.hasPending(1) }
        try await waitUntil { opens == 1 }
        let current = Task { await model.load(quality: 250) }
        try await waitUntil { await gate.hasPending(2) }
        let freshRoom = room(title: "当前房间")
        await gate.resolve(2, value: freshRoom)
        try await waitUntil { model.room == freshRoom }
        await current.value
        await gate.resolve(1, value: room(title: "旧房间", status: 0))
        await old.value

        XCTAssertEqual(model.room, freshRoom)
        XCTAssertFalse(model.isOffline)
        XCTAssertTrue(model.isPlaying)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(opens, 2, "Neither playback request waits for room metadata")
    }

    func testStopDuringSourceOpenRejectsItsCompletionAndRetainedCallback() async throws {
        let gate = LivePlayerResponseGate<Bool>()
        defer { Task { await gate.cancelAll() } }
        var callback: ((PlayerPlaybackEvent) -> Void)?
        let model = makeModel(playback: playback()) { session, _, _ in
            callback = session.onEvent
            _ = try await gate.load()
        }
        defer { model.stop() }
        let request = Task { await model.load() }
        try await waitUntil { await gate.hasPending(1) }
        model.stop()
        callback?(.firstFrame)
        callback?(.buffering(true))
        await gate.resolve(1, value: true)
        await request.value

        XCTAssertFalse(model.isPlaying)
        XCTAssertFalse(model.hasRenderedFirstFrame)
        XCTAssertFalse(model.isBuffering)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.session.onEvent)
    }

    func testNewQualityRejectsSupersededPlaybackFailure() async throws {
        let gate = LivePlayerResponseGate<LivePlayback>()
        defer { Task { await gate.cancelAll() } }
        let info = room()
        var opened: [URL] = []
        let model = LivePlayerModel(room: info, roomLoader: { _ in info },
                                    playbackLoader: { _, _ in try await gate.load() },
                                    sourceOpener: { session, source, _ in
            opened.append(source.video.primary)
            session.onEvent?(.firstFrame)
        }, publishesSystemMedia: false)
        defer { model.stop() }
        let old = Task { await model.load(quality: 10000) }
        try await waitUntil { await gate.hasPending(1) }
        let current = Task { await model.load(quality: 250) }
        try await waitUntil { await gate.hasPending(2) }
        let fresh = playback(quality: 250)
        await gate.resolve(2, value: fresh)
        await current.value
        let currentEngine = model.session
        await gate.fail(1)
        await old.value

        XCTAssertEqual(opened, [fresh.candidates[0].url])
        XCTAssertTrue(model.session === currentEngine)
        XCTAssertEqual(model.selectedQuality, 250)
        XCTAssertTrue(model.hasRenderedFirstFrame)
        XCTAssertTrue(model.isPlaying)
        XCTAssertNil(model.errorMessage)
    }

    func testFirstOpenFailureTriesBackupAndDoesNotExposeAnError() async throws {
        let payload = playback(candidateCount: 2)
        var opened: [URL] = []
        let model = makeModel(playback: payload) { session, source, startTime in
            opened.append(source.video.primary)
            XCTAssertEqual(startTime, 0)
            XCTAssertEqual(source.duration, 0)
            XCTAssertNil(source.audio)
            if opened.count == 1 { throw URLError(.cannotConnectToHost) }
            session.onEvent?(.firstFrame)
        }
        defer { model.stop() }
        await model.load()
        try await waitUntil { opened.count == 2 || model.errorMessage != nil }

        XCTAssertEqual(opened, payload.candidates.map(\.url))
        XCTAssertTrue(model.hasRenderedFirstFrame)
        XCTAssertTrue(model.isPlaying)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
    }

    func testStreamErrorChangesEngineAndRejectsRetainedOldCallbacks() async throws {
        let payload = playback(candidateCount: 2)
        var callbacks: [(PlayerPlaybackEvent) -> Void] = []
        let model = makeModel(playback: payload) { session, _, _ in
            if let callback = session.onEvent { callbacks.append(callback) }
            session.onEvent?(.firstFrame)
        }
        defer { model.stop() }
        await model.load()
        let firstEngine = model.session
        let firstCallback = try XCTUnwrap(callbacks.first)
        firstCallback(.error("当前线路断开"))
        try await waitUntil { callbacks.count == 2 }
        let backupEngine = model.session
        firstCallback(.error("旧线路迟到错误"))
        firstCallback(.displayAspectRatio(9.0 / 16))
        firstCallback(.playing(false))

        XCTAssertFalse(firstEngine === backupEngine)
        XCTAssertTrue(model.session === backupEngine)
        XCTAssertTrue(model.isPlaying)
        XCTAssertTrue(model.hasRenderedFirstFrame)
        XCTAssertNil(model.displayAspectRatio)
        XCTAssertNil(model.errorMessage)
    }

    func testLateOpenFailureCannotStopAnAlreadyRecoveredBackup() async throws {
        let gate = LivePlayerResponseGate<Bool>()
        defer { Task { await gate.cancelAll() } }
        var opened = 0
        let model = makeModel(playback: playback(candidateCount: 2)) { session, _, _ in
            opened += 1
            if opened == 1 {
                session.onEvent?(.error("首线路事件失败"))
                _ = try await gate.load()
            } else { session.onEvent?(.firstFrame) }
        }
        defer { model.stop() }
        let request = Task { await model.load() }
        try await waitUntil { await gate.hasPending(1) }
        try await waitUntil { opened == 2 && model.hasRenderedFirstFrame }
        let workingEngine = model.session
        await gate.fail(1)
        await request.value

        XCTAssertTrue(model.session === workingEngine)
        XCTAssertTrue(model.isPlaying)
        XCTAssertTrue(model.hasRenderedFirstFrame)
        XCTAssertNil(model.errorMessage)
    }

    func testFailureDuringBackupOpenContinuesToTheNextCandidate() async throws {
        var opened = 0
        let model = makeModel(playback: playback(candidateCount: 3)) { session, _, _ in
            opened += 1
            if opened < 3 { session.onEvent?(.error("线路不可用")) }
            else { session.onEvent?(.firstFrame) }
        }
        defer { model.stop() }
        await model.load()
        try await waitUntil { opened == 3 || model.errorMessage != nil }
        XCTAssertEqual(opened, 3)
        XCTAssertTrue(model.isPlaying)
        XCTAssertNil(model.errorMessage)
    }

    func testAllCandidatesFailOnceAndRetryCountIsBounded() async throws {
        var opened = 0
        let model = makeModel(playback: playback(candidateCount: 6)) { _, _, _ in
            opened += 1
            throw URLError(.cannotConnectToHost)
        }
        defer { model.stop() }
        await model.load()
        try await waitUntil { model.errorMessage != nil }
        XCTAssertEqual(opened, 4, "Only the first four server candidates may be tried")
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.isBuffering)
        XCTAssertFalse(model.isPlaying)
        XCTAssertNil(model.session.onEvent)
    }

    func testPauseBeforeFirstFrameAndQualityChangePreservePlaybackIntent() async {
        let info = room()
        let log = LivePlayerQualityLog()
        var callbacks: [(PlayerPlaybackEvent) -> Void] = []
        let model = LivePlayerModel(room: info, roomLoader: { _ in info }, playbackLoader: { _, quality in
            await log.append(quality)
            return LivePlayback(roomID: info.roomID, liveStatus: 1, isPortrait: false,
                                qualities: [LiveQuality(id: quality, name: "测试清晰度")],
                                candidates: [Self.candidate(quality: quality)])
        }, sourceOpener: { session, _, _ in
            if let callback = session.onEvent { callbacks.append(callback) }
        }, publishesSystemMedia: false)
        defer { model.stop() }
        await model.load()
        model.togglePlayback()
        callbacks.last?(.firstFrame)
        callbacks.last?(.playing(true))
        XCTAssertTrue(model.hasRenderedFirstFrame)
        XCTAssertFalse(model.isPlaying, "A late first frame cannot override pause")

        await model.load(quality: 250)
        XCTAssertEqual(model.selectedQuality, 250)
        XCTAssertFalse(model.hasRenderedFirstFrame)
        callbacks.last?(.firstFrame)
        callbacks.last?(.playing(true))
        XCTAssertFalse(model.isPlaying, "Quality changes must preserve paused intent")
        model.play()
        XCTAssertTrue(model.isPlaying)
        let requestedQualities = await log.values
        XCTAssertEqual(requestedQualities, [10000, 250])
    }

    func testFirstFrameAndBufferingEventsControlVisibleState() async {
        let model = makeModel(playback: playback(portrait: true)) { _, _, _ in }
        defer { model.stop() }
        await model.load()
        XCTAssertTrue(model.isLoading)
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(model.displayAspectRatio, 9.0 / 16)
        model.receive(.playing(true))
        XCTAssertFalse(model.isPlaying)
        model.receive(.buffering(true))
        XCTAssertTrue(model.isBuffering)
        model.receive(.firstFrame)
        model.receive(.buffering(false))
        XCTAssertTrue(model.isPlaying)
        XCTAssertFalse(model.isLoading)
        XCTAssertFalse(model.isBuffering)
        for ratio in [Double.nan, .infinity, 0, -1] { model.receive(.displayAspectRatio(ratio)) }
        XCTAssertEqual(model.displayAspectRatio, 9.0 / 16)
        model.receive(.displayAspectRatio(16.0 / 9))
        XCTAssertEqual(model.displayAspectRatio, 16.0 / 9)
    }

    func testLiveSystemMediaHasLiveFlagAndNoVODTimeline() {
        let metadata = SystemMediaMetadata(identifier: "live:17", title: "测试直播", artist: "测试主播",
                                            artworkURL: nil, isLiveStream: true)
        let info = SystemNowPlayingCenter.makeInfo(metadata: metadata, duration: 900, elapsed: 35, playbackRate: 1)
        XCTAssertEqual(info[MPNowPlayingInfoPropertyIsLiveStream] as? Bool, true)
        XCTAssertEqual(info[MPNowPlayingInfoPropertyExternalContentIdentifier] as? String, "live:17")
        XCTAssertNil(info[MPMediaItemPropertyPlaybackDuration])
        XCTAssertNil(info[MPNowPlayingInfoPropertyElapsedPlaybackTime])
        XCTAssertEqual(info[MPNowPlayingInfoPropertyPlaybackRate] as? Float, 1)
        XCTAssertEqual(info[MPNowPlayingInfoPropertyMediaType] as? UInt, MPNowPlayingInfoMediaType.video.rawValue)
    }

    private func makeModel(playback payload: LivePlayback, opener: @escaping PlaybackSourceOpener) -> LivePlayerModel {
        let info = room()
        return LivePlayerModel(room: info, roomLoader: { _ in info }, playbackLoader: { _, _ in payload },
                               sourceOpener: opener, publishesSystemMedia: false)
    }

    private func room(title: String = "测试直播", status: Int = 1) -> LiveRoom {
        LiveRoom(roomID: 17, title: title, username: "测试主播", liveStatus: status)
    }

    private func playback(status: Int = 1, quality: Int = 10000, candidateCount: Int = 1,
                          portrait: Bool = false) -> LivePlayback {
        LivePlayback(roomID: 17, liveStatus: status, isPortrait: portrait,
                     qualities: [LiveQuality(id: quality, name: "测试清晰度")],
                     candidates: (0..<candidateCount).map { Self.candidate(index: $0, quality: quality) })
    }

    private nonisolated static func candidate(index: Int = 0, quality: Int = 10000) -> LiveStreamCandidate {
        LiveStreamCandidate(url: URL(string: "https://stream\(index).example.invalid/live/\(quality).m3u8")!,
                            protocolName: "http_hls", formatName: "ts", codecName: "avc", quality: quality)
    }

    private func waitUntil(_ predicate: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("The injected live request or recovery did not complete")
        throw CancellationError()
    }
}

private actor LivePlayerResponseGate<Value: Sendable> {
    private(set) var requestCount = 0
    private var pending: [Int: CheckedContinuation<Value, any Error>] = [:]

    func load() async throws -> Value {
        requestCount += 1
        let index = requestCount
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }

    func hasPending(_ index: Int) -> Bool { pending[index] != nil }
    func resolve(_ index: Int, value: Value) { pending.removeValue(forKey: index)?.resume(returning: value) }
    func fail(_ index: Int) { pending.removeValue(forKey: index)?.resume(throwing: URLError(.cannotConnectToHost)) }
    func cancelAll() {
        let continuations = Array(pending.values)
        pending.removeAll()
        for continuation in continuations { continuation.resume(throwing: CancellationError()) }
    }
}

private actor LivePlayerQualityLog {
    private(set) var values: [Int] = []
    func append(_ quality: Int) { values.append(quality) }
}
