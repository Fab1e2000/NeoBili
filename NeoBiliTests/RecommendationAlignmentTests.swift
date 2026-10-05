import XCTest
import Synchronization
@testable import NeoBili

@MainActor
final class RecommendationAlignmentTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "alignment.tests.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testRefreshRetainsLastAcceptedCursorAcrossFailureAndTerminalPage() async {
        var requests: [RecommendationRequest] = []
        var login = UUID()
        let model = HomeViewModel(defaults: defaults(),
            currentAccount: { HomeFeedAccount(accountID: 42, hasAppCredential: true) },
            currentSessionID: { login }, fetchRecommendations: { request in
                requests.append(request)
                if requests.count == 2 { throw URLError(.timedOut) }
                return RecommendationBatch(videos: [], nextRequest: nil, appCursor: 123)
            })
        await model.loadInitial()
        await model.refresh()
        await model.refresh()
        XCTAssertEqual(requests.map(\.appCursor), [0, 123, 123])
        XCTAssertEqual(requests[1], requests[2], "Failure must not reset the refresh cursor")
        login = UUID() // Same account relogin is still a different credential session.
        await model.refresh()
        XCTAssertEqual(requests.last?.appCursor, 0)
    }

    func testMetricsSeparateWatchedTimeFromResumeSeekAndPause() {
        var progress = PlaybackWatchProgress()
        progress.setPaused(true, at: -100) // Preload is not a playback pause.
        progress.setPaused(false, at: 0)
        XCTAssertNil(progress.observe(position: 90, at: 0, isActive: true))
        XCTAssertNil(progress.observe(position: 92, at: 2, isActive: true))
        progress.interrupt(discontinuity: true)
        XCTAssertNil(progress.observe(position: 250, at: 3, isActive: true))
        XCTAssertNil(progress.observe(position: 252, at: 5, isActive: true, isMiniPlayer: true))
        progress.setPaused(true, at: 5)
        progress.interrupt()
        progress.setPaused(false, at: 15)
        let report = progress.report(position: 252, duration: 300, startTimestamp: 100,
            sourceFields: [:], at: 15)
        XCTAssertEqual(report.watchedTime, 4)
        XCTAssertEqual(report.pausedTime, 10)
        XCTAssertEqual(report.mobileParameters["played_time"], "4")
        XCTAssertEqual(report.mobileParameters["last_play_progress_time"], "252")
        XCTAssertEqual(report.mobileParameters["total_time"], "14")
        XCTAssertEqual(report.mobileParameters["miniplayer_play_time"], "2")
        XCTAssertEqual(report.mobileParameters["max_play_progress_time"], "252")
    }

    func testTrackingIsDroppedAcrossAccountSessionsAndUnknownEntryIsNotRecommendation() {
        let session = UUID()
        var entry = PlaybackEntry.recommendation(trackID: "fixture-track", reportFlowData: "fixture-flow")
        entry.loginSessionID = session
        XCTAssertEqual(entry.parameters(for: session)["track_id"], "fixture-track")
        XCTAssertNil(entry.parameters(for: UUID())["track_id"])
        XCTAssertNil(entry.parameters(for: UUID())["report_flow_data"])
        XCTAssertEqual(PlaybackEntry.history.parameters()["from_spmid"], "main.my-history.0.0")
        XCTAssertEqual(PlaybackEntry.search.parameters()["from"], "3")
        XCTAssertEqual(PlaybackEntry.related.parameters()["from"], "2")
    }

    func testDeviceIsStableButAppSessionRotatesOnSameAccountRelogin() async throws {
        let identity = DeviceIdentity(defaults: defaults(), credentials: .memory(), allowsNetwork: false,
                                      purgeCookies: {})
        await identity.saveLogin(.init(sessdata: "fixture", biliJct: "csrf", dedeUserID: "42"), accessKey: "token")
        let oldSession = identity.loginSessionID
        let first = try await identity.appRequestHeaders(expectedSessionID: oldSession)
        let second = try await identity.appRequestHeaders(expectedSessionID: oldSession)
        XCTAssertEqual(first["buvid"], second["buvid"])
        XCTAssertEqual(first["session_id"], second["session_id"])
        await identity.saveLogin(.init(sessdata: "fixture", biliJct: "csrf", dedeUserID: "42"), accessKey: "token2")
        let next = try await identity.appRequestHeaders(expectedSessionID: identity.loginSessionID)
        XCTAssertEqual(first["buvid"], next["buvid"])
        XCTAssertNotEqual(first["session_id"], next["session_id"])
        do {
            _ = try await identity.appRequestHeaders(expectedSessionID: oldSession)
            XCTFail("Old session must be rejected")
        } catch is CancellationError {} catch { XCTFail("Unexpected error") }
    }

    func testMobileWatchAndHistoryUseOwnSignedCredentialWithNoWebDuplicate() async throws {
        let identity = DeviceIdentity(defaults: defaults(), credentials: .memory(), allowsNetwork: false,
                                      purgeCookies: {})
        await identity.saveLogin(.init(sessdata: "fixture", biliJct: "csrf", dedeUserID: "42"), accessKey: "own-token")
        let sessionID = identity.loginSessionID
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AlignmentProtocol.self]
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel() }
        AlignmentProtocol.requests.withLock { $0 = [] }
        AlignmentProtocol.rejectHeartbeat.withLock { $0 = false }
        let client = APIClient(session: transport, appAuthentication: { await identity.appAccount() })
        let report = PlaybackWatchReport(position: 120, watchedTime: 20, pausedTime: 3,
            maximumPosition: 120, duration: 300, startTimestamp: 100,
            sourceFields: PlaybackEntry.recommendation(trackID: "fixture-track", reportFlowData: nil).parameters())
        try await BiliAPI.reportAppWatch(bvid: "BVFixture", aid: 1, cid: 2, report: report,
                                        expectedSessionID: sessionID, client: client, identity: identity)
        let requests = AlignmentProtocol.requests.withLock { $0 }
        XCTAssertEqual(requests.map { $0.url!.path }, ["/x/report/heartbeat/mobile", "/x/v2/history/report"])
        for request in requests {
            XCTAssertEqual(request.url?.host, "api.bilibili.com")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            XCTAssertFalse(request.httpShouldHandleCookies)
            let query = URLComponents(string: "https://fixture.invalid/?" + String(data: request.httpBody!, encoding: .utf8)!)!
            let form = Dictionary(uniqueKeysWithValues: query.queryItems!.map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(form["access_key"], "own-token")
            XCTAssertEqual(form["sign"], AppSigner.signed(form, timestamp: Int(form["ts"]!)!)["sign"])
            if request.url!.path.contains("heartbeat") {
                XCTAssertEqual(form["played_time"], "20")
                XCTAssertEqual(form["last_play_progress_time"], "120")
                XCTAssertEqual(form["track_id"], "fixture-track")
                XCTAssertEqual(form["session"]?.count, 32)
                XCTAssertEqual(form["session"], form["sessionID"])
                XCTAssertEqual(request.value(forHTTPHeaderField: "session_id")?.count, 8)
            } else { XCTAssertEqual(form["progress"], "120") }
        }
        await identity.clearLoginCookies()
        do {
            try await BiliAPI.reportAppWatch(bvid: "BVFixture", aid: 1, cid: 2, report: report,
                                            expectedSessionID: sessionID, client: client, identity: identity)
            XCTFail("Old account write must be rejected")
        } catch is CancellationError {} catch { XCTFail("Unexpected error") }
        XCTAssertEqual(AlignmentProtocol.requests.withLock { $0.count }, 2)
    }

    func testRejectedMobileHeartbeatStillSyncsHistoryAndCookieOnlyUsesOneWebRequest() async throws {
        let identity = DeviceIdentity(defaults: defaults(), credentials: .memory(), allowsNetwork: false,
                                      purgeCookies: {})
        await identity.saveLogin(.init(sessdata: "fixture", biliJct: "csrf", dedeUserID: "42"), accessKey: "own-token")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AlignmentProtocol.self]
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel() }
        let client = APIClient(session: transport,
            authentication: { await identity.authenticatedRequestSnapshot() },
            appAuthentication: { await identity.appAccount() })
        let report = PlaybackWatchReport(position: 20, watchedTime: 5, pausedTime: 0,
            maximumPosition: 20, duration: 300, startTimestamp: 100, sourceFields: [:])
        AlignmentProtocol.requests.withLock { $0 = [] }
        AlignmentProtocol.rejectHeartbeat.withLock { $0 = true }
        defer { AlignmentProtocol.rejectHeartbeat.withLock { $0 = false } }
        do {
            try await BiliAPI.reportAppWatch(bvid: "BVFixture", aid: 1, cid: 2, report: report,
                expectedSessionID: identity.loginSessionID, client: client, identity: identity)
            XCTFail("Rejected heartbeat must surface its error")
        } catch BiliAPIError.apiError(let code, _) { XCTAssertEqual(code, -400) }
        XCTAssertEqual(AlignmentProtocol.requests.withLock { $0.map { $0.url!.path } },
                       ["/x/report/heartbeat/mobile", "/x/v2/history/report"])
        await identity.setAccessKey(nil)
        AlignmentProtocol.requests.withLock { $0 = [] }
        try await BiliAPI.reportAppWatch(bvid: "BVFixture", aid: 1, cid: 2, report: report,
            expectedSessionID: identity.loginSessionID, client: client, identity: identity)
        XCTAssertEqual(AlignmentProtocol.requests.withLock { $0.map { $0.url!.path } },
                       ["/x/click-interface/web/heartbeat"])
    }

    func testZeroStartAndHistoryCheckpointHaveSeparateTransports() async throws {
        let identity = DeviceIdentity(defaults: defaults(), credentials: .memory(), allowsNetwork: false, purgeCookies: {})
        await identity.saveLogin(.init(sessdata: "fixture", biliJct: "csrf", dedeUserID: "42"), accessKey: "own-token")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AlignmentProtocol.self]
        let transport = URLSession(configuration: configuration)
        defer { transport.invalidateAndCancel() }
        let client = APIClient(session: transport, appAuthentication: { await identity.appAccount() })
        AlignmentProtocol.requests.withLock { $0 = [] }
        AlignmentProtocol.rejectHeartbeat.withLock { $0 = false }
        var report = PlaybackWatchReport(position: 0, watchedTime: 0, pausedTime: 0,
            maximumPosition: 0, duration: 300, startTimestamp: 100, sourceFields: [:],
            playbackSession: "own-playback", delivery: .start)
        try await BiliAPI.reportAppWatch(bvid: "BVFixture", aid: 1, cid: 2, report: report,
            expectedSessionID: identity.loginSessionID, client: client, identity: identity)
        XCTAssertEqual(AlignmentProtocol.requests.withLock { $0.map { $0.url!.path } }, ["/x/report/heartbeat/mobile"])
        report = PlaybackWatchReport(position: 15, watchedTime: 15, pausedTime: 0,
            maximumPosition: 15, duration: 300, startTimestamp: 100, sourceFields: [:],
            playbackSession: "own-playback", delivery: .checkpoint)
        try await BiliAPI.reportAppWatch(bvid: "BVFixture", aid: 1, cid: 2, report: report,
            expectedSessionID: identity.loginSessionID, client: client, identity: identity)
        XCTAssertEqual(AlignmentProtocol.requests.withLock { $0.map { $0.url!.path } },
            ["/x/report/heartbeat/mobile", "/x/v2/history/report"])
    }
}

private final class AlignmentProtocol: URLProtocol, @unchecked Sendable {
    static let requests = Mutex<[URLRequest]>([])
    static let rejectHeartbeat = Mutex(false)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            var body = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                guard count > 0 else { break }
                body.append(contentsOf: bytes.prefix(count))
            }
            captured.httpBody = body
        }
        Self.requests.withLock { $0.append(captured) }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        let rejected = request.url!.path == "/x/report/heartbeat/mobile" && Self.rejectHeartbeat.withLock { $0 }
        client?.urlProtocol(self, didLoad: Data((rejected ? #"{"code":-400,"message":"fixture rejection"}"#
            : #"{"code":0,"data":{}}"#).utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
