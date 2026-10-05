import XCTest
import Synchronization
@testable import NeoBili

@MainActor
final class RecommendationBehaviorTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "behavior.tests.\(UUID())"
        let value = UserDefaults(suiteName: name)!
        addTeardownBlock { value.removePersistentDomain(forName: name) }
        return value
    }
    private func video(session: UUID) -> VideoSummary {
        var video = VideoSummary(bvid: "BVFixture", aid: 1, cid: 2, title: "Fixture", pic: "", desc: "",
            duration: 300, pubdate: 0, owner: .init(mid: 7, name: "owner", face: ""),
            stat: .init(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0))
        video.playbackEntry = .init(source: .recommendation, trackID: "card-track", reportFlowData: "flow", loginSessionID: session)
        video.recommendationClickFields = ["param": "1", "title": "Fixture", "goto": "av", "card_type": "small_cover_v2"]
        return video
    }

    func testActualPlaybackHasZeroStartAndOneFinishWithIndependentPageSession() async throws {
        let reports = BehaviorReports()
        var clock = 0.0
        let page = VideoDetailViewModel(bvid: "BVFixture")
        let player = PlayerViewModel(bvid: "BVFixture", cid: 2, aid: 1,
            watchReportReporter: { await reports.append($0) },
            progressStore: PlaybackProgressStore(defaults: defaults()), watchProgressClock: { clock })
        player.session.onEvent?(.duration(300))
        player.session.onEvent?(.firstFrame)
        player.session.onEvent?(.playing(true))
        player.session.onEvent?(.position(0))
        for value in 1...169 { clock = Double(value); player.session.onEvent?(.position(clock)) }
        player.pause()
        clock += 10
        player.session.onEvent?(.playing(true))
        player.session.onEvent?(.position(169))
        clock += 1; player.session.onEvent?(.position(170))
        player.stop(); player.stop()
        let values = await reports.waitForFinish()
        let mobile = values.filter { $0.delivery != .checkpoint }
        XCTAssertEqual(mobile.map(\.delivery), [.start, .finish])
        XCTAssertEqual(mobile[0].watchedTime, 0)
        XCTAssertEqual(mobile[0].maximumPosition, 0)
        XCTAssertEqual(mobile[1].watchedTime, 170, accuracy: 0.01)
        XCTAssertEqual(mobile[1].pausedTime, 10, accuracy: 0.01)
        XCTAssertEqual(mobile[1].position, 170)
        XCTAssertEqual(mobile[0].playbackSession, mobile[1].playbackSession)
        XCTAssertNotEqual(mobile[0].playbackSession, page.appPlaybackSession)
        XCTAssertEqual(mobile[0].playbackSession.count, 32)
        XCTAssertTrue(values.contains { $0.delivery == .checkpoint }, "independent history sync remains")
    }

    func testPreloadSeekAndNoRealPlaybackProduceNoMobileEvents() async {
        let reports = BehaviorReports()
        let player = PlayerViewModel(bvid: "BVFixture", cid: 2, aid: 1,
            watchReportReporter: { await reports.append($0) }, progressStore: PlaybackProgressStore(defaults: defaults()))
        player.session.onEvent?(.firstFrame)
        await player.seek(to: 200)
        player.session.onEvent?(.seekCompleted(200))
        player.pause(); player.stop()
        await Task.yield()
        let values = await reports.values
        XCTAssertTrue(values.isEmpty)
    }

    func testQuickExitKeepsBothBoundariesAndActualFractionalWatchTime() async {
        let reports = BehaviorReports()
        var clock = 0.0
        let player = PlayerViewModel(bvid: "BVFixture", cid: 2, aid: 1,
            watchReportReporter: { await reports.append($0) },
            progressStore: PlaybackProgressStore(defaults: defaults()), watchProgressClock: { clock })
        player.session.onEvent?(.firstFrame); player.session.onEvent?(.playing(true))
        player.session.onEvent?(.position(0))
        clock = 0.3; player.session.onEvent?(.position(0.3)); player.stop()
        let values = await reports.waitForFinish()
        XCTAssertEqual(values.map(\.delivery), [.start, .finish])
        XCTAssertEqual(values.last?.watchedTime ?? 0, 0.3, accuracy: 0.01)
    }

    func testLateAidStillStartsBeforeFinishingAndDoesNotStartAfterStop() async {
        let reports = BehaviorReports()
        var clock = 0.0
        let player = PlayerViewModel(bvid: "BVFixture", cid: 2,
            watchReportReporter: { await reports.append($0) },
            progressStore: PlaybackProgressStore(defaults: defaults()), watchProgressClock: { clock })
        player.session.onEvent?(.firstFrame); player.session.onEvent?(.playing(true))
        player.session.onEvent?(.position(0))
        clock = 0.3; player.session.onEvent?(.position(0.3))
        player.updateWatchAid(1); player.stop(); player.updateWatchAid(1)
        let values = await reports.waitForFinish()
        XCTAssertEqual(values.map(\.delivery), [.start, .finish])
        XCTAssertEqual(values.map(\.aid), [1, 1])
    }

    func testWriterDoesNotCoalesceBoundariesOfReopenedSameVideo() async {
        let reports = BehaviorReports()
        let gate = BehaviorGate()
        let started = expectation(description: "first start in flight")
        let sender = PlaybackWatchReportSender { report in
            await reports.append(report)
            if report.playbackSession == "first", report.delivery == .start {
                started.fulfill(); await gate.wait()
            }
        }
        func report(_ session: String, _ delivery: PlaybackWatchReport.Delivery) -> PlaybackWatchReport {
            .init(position: 1, watchedTime: 1, pausedTime: 0, maximumPosition: 1, duration: 10,
                startTimestamp: 1, sourceFields: [:], playbackSession: session, delivery: delivery)
        }
        sender.enqueue(report("first", .start))
        await fulfillment(of: [started], timeout: 1)
        sender.enqueue(report("first", .finish)); sender.enqueue(report("second", .start))
        sender.enqueue(report("second", .finish)); await gate.release()
        let values = await reports.waitForCount(4)
        XCTAssertEqual(values.map(\.playbackSession), ["first", "first", "second", "second"])
        XCTAssertEqual(values.map(\.delivery), [.start, .finish, .start, .finish])
    }

    func testRecordIOGoldenFramingAndGzipRoundTrip() throws {
        let record = RecommendationRecordIO.encode(metadata: [("eventId", "test"), ("platform", "1")], payload: Data([8, 1]))
        XCTAssertEqual(record.map { String(format: "%02x", $0) }.joined(),
            "5244494f8000002073076576656e744964800000047465737408706c6174666f726d00000001310801")
        XCTAssertEqual(try AppProto.gunzip(RecommendationRecordIO.gzip(record)), record)
    }

    func testClickSnapshotPersistsAcrossRestartAndDropsOtherAccount() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = defaults(), credentials = CredentialStorage.memory()
        let first = DeviceIdentity(defaults: settings, credentials: credentials, allowsNetwork: false, purgeCookies: {})
        await first.saveLogin(.init(sessdata: "private-cookie", biliJct: "private-csrf", dedeUserID: "42"), accessKey: "private-token")
        let login = first.loginSessionID
        let original = try await first.appDeviceSnapshot(expectedSessionID: login)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BehaviorProtocol.self]
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel() }
        BehaviorProtocol.state.withLock { $0 = .init(failsOffline: true) }
        let client = APIClient(session: transport, appAuthentication: { await first.appAccount() })
        let reporter = RecommendationClickReporter(directory: directory, identity: first, client: client)
        await reporter.record(video(session: login), session: login, timestamp: Int(Date().timeIntervalSince1970 * 1000))
        let file = directory.appendingPathComponent("pending.json")
        let saved = try String(contentsOf: file, encoding: .utf8)
        for secret in ["private-cookie", "private-csrf", "private-token"] { XCTAssertFalse(saved.contains(secret)) }
        let second = DeviceIdentity(defaults: settings, credentials: credentials, allowsNetwork: false, purgeCookies: {})
        let current = try await second.appDeviceSnapshot(expectedSessionID: second.loginSessionID)
        XCTAssertNotEqual(current.requestSession, original.requestSession)
        BehaviorProtocol.state.withLock { $0 = .init(failsOffline: false) }
        let secondClient = APIClient(session: transport, appAuthentication: { await second.appAccount() })
        let restored = RecommendationClickReporter(directory: directory, identity: second, client: secondClient)
        await restored.flush()
        let request = try XCTUnwrap(BehaviorProtocol.state.withLock { $0.requests.first })
        XCTAssertEqual(request.url?.path, "/log/pbmobile/unrealtime")
        XCTAssertEqual(request.url?.query, "ios")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(request.value(forHTTPHeaderField: "authorization"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "session_id"), current.requestSession)
        let proto = try decodeRecord(try AppProto.gunzip(XCTUnwrap(request.httpBody)))
        XCTAssertEqual(proto.text(1), RecommendationClick.event)
        XCTAssertEqual(proto.text(4), "42")
        XCTAssertEqual(proto.messages(2).first?.text(15), original.requestSession)
        XCTAssertEqual(proto.messages(2).first?.number(1), 1, "Chinese identity must not copy international appId")
        XCTAssertNil(proto.messages(2).first?.data(14), "unknown official fingerprint must not be copied")
        let extras = Dictionary(uniqueKeysWithValues: proto.messages(13).map { ($0.text(1)!, $0.text(2) ?? "") })
        XCTAssertEqual(extras["param"], "1"); XCTAssertEqual(extras["track_id"], "card-track")
        XCTAssertEqual(extras["event"], "card_click")
        XCTAssertNil(extras["tm_card_play_state"], "do not invent an inline preview")
        let savedAfter = try JSONDecoder().decode([RecommendationClick].self, from: Data(contentsOf: file))
        XCTAssertTrue(savedAfter.isEmpty)

        BehaviorProtocol.state.withLock { $0 = .init(failsOffline: true) }
        let oldLogin = second.loginSessionID
        await restored.record(video(session: oldLogin), session: oldLogin, timestamp: Int(Date().timeIntervalSince1970 * 1000))
        await second.saveLogin(.init(sessdata: "new-login", biliJct: "csrf", dedeUserID: "42"), accessKey: "new-token")
        let third = DeviceIdentity(defaults: settings, credentials: credentials, allowsNetwork: false, purgeCookies: {})
        let thirdClient = APIClient(session: transport, appAuthentication: { await third.appAccount() })
        BehaviorProtocol.state.withLock { $0 = .init(failsOffline: false) }
        let afterRelogin = RecommendationClickReporter(directory: directory, identity: third, client: thirdClient)
        await afterRelogin.flush()
        XCTAssertTrue(BehaviorProtocol.state.withLock { $0.requests.isEmpty }, "same-account relogin invalidates persisted old events even after restart")

        BehaviorProtocol.state.withLock { $0 = .init(failsOffline: true) }
        let session = second.loginSessionID
        await restored.record(video(session: session), session: session, timestamp: Int(Date().timeIntervalSince1970 * 1000))
        await second.saveLogin(.init(sessdata: "next", biliJct: "next", dedeUserID: "43"), accessKey: "next")
        BehaviorProtocol.state.withLock { $0 = .init(failsOffline: false) }
        await restored.flush()
        XCTAssertTrue(BehaviorProtocol.state.withLock { $0.requests.isEmpty })
        await restored.record(video(session: session), session: session, timestamp: Int(Date().timeIntervalSince1970 * 1000))
        XCTAssertTrue(BehaviorProtocol.state.withLock { $0.requests.isEmpty }, "late old UI click is rejected")
    }

    private func decodeRecord(_ data: Data) throws -> AppProto {
        let b = [UInt8](data)
        XCTAssertEqual(String(bytes: b.prefix(4), encoding: .utf8), "RDIO")
        var offset = 9, more = b[4] & 128 != 0
        while more {
            let name = Int(b[offset]); offset += 1 + name
            let size = b[offset..<(offset + 4)].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            offset += 4; more = size & 0x80000000 != 0; offset += Int(size & 0x7fffffff)
        }
        return try AppProto(Data(b[offset...]))
    }
}

private actor BehaviorReports {
    private(set) var values: [PlaybackWatchReport] = []
    func append(_ value: PlaybackWatchReport) { values.append(value) }
    func waitForFinish() async -> [PlaybackWatchReport] {
        for _ in 0..<200 { if values.last?.delivery == .finish { return values }; try? await Task.sleep(for: .milliseconds(5)) }
        return values
    }
    func waitForCount(_ count: Int) async -> [PlaybackWatchReport] {
        for _ in 0..<200 { if values.count >= count { return values }; try? await Task.sleep(for: .milliseconds(5)) }
        return values
    }
}
private actor BehaviorGate {
    var continuation: CheckedContinuation<Void, Never>?
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}
private final class BehaviorProtocol: URLProtocol, @unchecked Sendable {
    struct State { var failsOffline: Bool; var requests: [URLRequest] = [] }
    static let state = Mutex(State(failsOffline: false))
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if Self.state.withLock({ $0.failsOffline }) {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
        }
        var captured = request
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096), data = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }; data.append(contentsOf: bytes.prefix(count))
            }
            captured.httpBody = data
        }
        Self.state.withLock { $0.requests.append(captured) }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"code":0}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
