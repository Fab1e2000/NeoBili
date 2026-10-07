import XCTest
import Synchronization
@testable import NeoBili

@MainActor
final class OfficialBehaviorAdoptionTests: XCTestCase {
    func testExposureRevisitHasOneShowAndTwoIndependentIntervals() {
        var events: [RecommendationExposureTracker.Event] = []
        let tracker = RecommendationExposureTracker { events.append($0) }
        var video = VideoSummary(bvid: "fixture", aid: 1, cid: 2, title: "", pic: "", desc: "", duration: 241,
            pubdate: 0, owner: .init(mid: 1, name: "", face: ""), stat: .init(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0))
        video.playbackEntry = .init(source: .recommendation, trackID: "batch", loginSessionID: UUID())
        let card = RecommendationExposureTracker.Card(video: video, position: 2)
        tracker.update([card], timestamp: 1000)
        tracker.update([card], timestamp: 2000)
        tracker.update([], timestamp: 11000)
        tracker.update([card], timestamp: 20000)
        tracker.update([], timestamp: 30000)
        XCTAssertEqual(events.map(\.name), ["tm.recommend.feed-card.0.show",
            "tm.recommend.feed-card.duration.show", "tm.recommend.feed-card.duration.show"])
        XCTAssertEqual(events[1].start, 1000); XCTAssertEqual(events[1].end, 11000)
        XCTAssertEqual(events[2].start, 20000); XCTAssertEqual(events[2].end, 30000)
        video.playbackEntry.trackID = "next-batch"
        tracker.update([.init(video: video, position: 2)], timestamp: 40000)
        XCTAssertEqual(events.last?.name, "tm.recommend.feed-card.0.show")
    }

    func testPlayerAndExposureProtobufUseTheirOwnCategoriesAndSubmessages() throws {
        let context = AppDeviceSnapshot(buvid: "own", requestSession: "app", startSession: "launch", mid: 1,
            accountEpoch: "local", model: "fixture", version: "9.13.0", build: "91300100")
        let player = AppProto.string(6, "150648") + AppProto.string(7, "1") + AppProto.string(14, "playback")
        let encoded = AppBehaviorEncoder.payload(context: context, timestamp: 1000,
            fields: ["event_policy": "0", "track_id": "batch"], name: "player.player.end.all.player",
            category: 9, player: player, uploadTime: 4000)
        let decoded = try AppProto(encoded)
        XCTAssertEqual(decoded.number(9), 9)
        XCTAssertEqual(decoded.messages(17).first?.text(6), "150648")
        XCTAssertEqual(decoded.messages(17).first?.text(14), "playback")
        XCTAssertEqual(decoded.messages(2).first?.text(15), "app")
        XCTAssertNil(decoded.data(11), "player event is not a click")
        let exposure = try AppProto(AppBehaviorEncoder.payload(context: context, timestamp: 1000,
            fields: ["param": "1", "event_policy": "1"], name: "tm.recommend.feed-card.0.show",
            category: 3, player: nil, uploadTime: 4000))
        XCTAssertEqual(exposure.number(9), 3)
        XCTAssertEqual(exposure.messages(12).first?.messages(1).first?.text(1), "tm.recommend.feed-card.0.show")
        XCTAssertNil(exposure.data(17))
    }

    func testServerStartTimestampIsScopedToPlaybackAndDoesNotChangeHistoryClock() async {
        let reports = AdoptionReports()
        let sender = PlaybackWatchReportSender(serverReport: { value in
            await reports.append(value)
            return value.delivery == .start ? (value.playbackSession == "one" ? 111 : 222) : nil
        }, receivesAcknowledgements: true)
        for (session,delivery) in [("one",PlaybackWatchReport.Delivery.start),("one",.checkpoint),("one",.finish),("two",.start),("two",.finish)] {
            var report = PlaybackWatchReport(position: 151, watchedTime: 140, pausedTime: 0, maximumPosition: 151,
                duration: 241, startTimestamp: 0, sourceFields: [:], playbackSession: session, delivery: delivery)
            report.localStartTimestamp = 999
            sender.enqueue(report)
        }
        let values = await reports.waitForCount(5)
        XCTAssertEqual(values.map(\.startTimestamp), [0,111,111,0,222])
        XCTAssertEqual(values.map(\.localStartTimestamp), [999,999,999,999,999])
        let history = AppWatchProtocol.historyParameters(aid: 1,cid: 2,report: values[2],deviceTimestamp: 1000)
        XCTAssertEqual(history["start_ts"], "999")
        XCTAssertEqual(values[2].mobileParameters["played_time"], "140")
        XCTAssertEqual(values[2].mobileParameters["last_play_progress_time"], "151")
    }

    func testOwnBuvidGenerationAndExistingIdentityPreservation() async {
        let vendor = "01234567-89AB-CDEF-0123-456789ABCDEF"
        XCTAssertEqual(AppBuvid.generate(idfv: vendor), "Y2C6" + vendor.replacingOccurrences(of: "-",with: ""))
        XCTAssertNil(AppBuvid.generate(idfv: String(repeating: "0", count: 32)))
        let suite = "adoption.\(UUID())", settings = UserDefaults(suiteName: suite)!
        defer { settings.removePersistentDomain(forName: suite) }
        settings.set("existing-device", forKey: "neobili.appBuvid")
        let identity = DeviceIdentity(defaults: settings,credentials: .memory(),allowsNetwork: false,
            vendorIdentifier: { vendor },purgeCookies: {})
        let value = await identity.appBuvid()
        XCTAssertEqual(value, "existing-device")
    }

    func testDeviceModePreferenceAppliesOnlyToNewIdentity() async throws {
        let suite = "device-mode.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(AppBuvid.selectedMode(defaults: defaults), .system)
        defaults.set("invalid", forKey: AppBuvid.modeKey)
        XCTAssertEqual(AppBuvid.selectedMode(defaults: defaults), .system)
        defaults.set("system", forKey: AppBuvid.modeKey)
        defaults.set("original", forKey: "neobili.appBuvid")
        let credentials = CredentialStorage.memory()
        let active = DeviceIdentity(defaults: defaults,
            randomBuvidExperiment: AppBuvid.selectedMode(defaults: defaults) == .random,
            credentials: credentials, allowsNetwork: false)
        defaults.set("random", forKey: AppBuvid.modeKey)
        XCTAssertEqual(AppBuvid.selectedMode(defaults: defaults), .random)
        let unchanged = await active.appBuvid()
        XCTAssertEqual(unchanged, "original", "Changing settings must not change in-flight identity")
        let restarted = DeviceIdentity(defaults: defaults,
            randomBuvidExperiment: AppBuvid.selectedMode(defaults: defaults) == .random,
            credentials: credentials, allowsNetwork: false)
        let random = await restarted.appBuvid()
        XCTAssertNotEqual(random, unchanged)
        defaults.set("system", forKey: AppBuvid.modeKey)
        let restored = DeviceIdentity(defaults: defaults,
            randomBuvidExperiment: AppBuvid.selectedMode(defaults: defaults) == .random,
            credentials: credentials, allowsNetwork: false)
        let original = await restored.appBuvid()
        XCTAssertEqual(original, unchanged)
    }

    func testRandomBuvidExperimentIsStableAndPreservesNormalIdentity() async throws {
        let suite = "random-buvid.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let credentials = CredentialStorage.memory()
        defaults.set("original-device", forKey: "neobili.appBuvid")
        credentials.write("original-device", "neobili.appBuvid")
        let experimental = DeviceIdentity(defaults: defaults, randomBuvidExperiment: true,
            credentials: credentials, allowsNetwork: false)
        let value = await experimental.appBuvid()
        XCTAssertEqual(value.count, 36)
        XCTAssertEqual(value, AppBuvid.generate(idfv: String(value.dropFirst(4))))
        XCTAssertNotEqual(value, "original-device")
        let restarted = DeviceIdentity(defaults: defaults, randomBuvidExperiment: true,
            credentials: credentials, allowsNetwork: false)
        let repeated = await restarted.appBuvid()
        XCTAssertEqual(value, repeated)
        defaults.removeObject(forKey: "neobili.experiment.randomBuvid.v1")
        let restored = DeviceIdentity(defaults: defaults, randomBuvidExperiment: true,
            credentials: credentials, allowsNetwork: false)
        let restoredValue = await restored.appBuvid()
        XCTAssertEqual(value, restoredValue, "Restore the experiment identity from its own credential key")
        let normal = DeviceIdentity(defaults: defaults, credentials: credentials, allowsNetwork: false)
        let normalValue = await normal.appBuvid()
        XCTAssertEqual(normalValue, "original-device")
        XCTAssertEqual(credentials.read("neobili.appBuvid"), "original-device")
    }

    func testRandomBuvidRegistrationAndTicketsHaveSeparateStorage() {
        let credentials = CredentialStorage.memory()
        let experiment = AppBuvid.experimentRegistrationStorage(credentials)
        for key in ["neobili.ios.guest.id", "neobili.ios.fingerprint.registration", "neobili.app.ticket"] {
            credentials.write("original", key)
            XCTAssertNil(experiment.read(key))
            experiment.write("experiment", key)
            XCTAssertEqual(credentials.read(key), "original")
            XCTAssertEqual(AppBuvid.experimentRegistrationStorage(credentials).read(key), "experiment")
        }
    }

    func testMobileStartDecodesServerTimeWithoutWritingZeroHistory() async throws {
        let suite = "ack.\(UUID())", settings = UserDefaults(suiteName: suite)!
        defer { settings.removePersistentDomain(forName: suite) }
        let identity = DeviceIdentity(defaults: settings, credentials: .memory(), allowsNetwork: false,
            vendorIdentifier: { "01234567-89AB-CDEF-0123-456789ABCDEF" }, purgeCookies: {})
        await identity.saveLogin(.init(sessdata: "fixture", biliJct: "fixture", dedeUserID: "1"), accessKey: "fixture")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AdoptionProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        AdoptionProtocol.paths.withLock { $0 = [] }
        let client = APIClient(session: session, appAuthentication: { await identity.appAccount() })
        let report = PlaybackWatchReport(position: 0, watchedTime: 0, pausedTime: 0, maximumPosition: 0,
            duration: 241, startTimestamp: 0, sourceFields: [:], playbackSession: "fixture-play", delivery: .start)
        let time = try await BiliAPI.reportAppWatch(bvid: "fixture", aid: 1, cid: 2, report: report,
            expectedSessionID: identity.loginSessionID, client: client, identity: identity)
        XCTAssertEqual(time, 321)
        XCTAssertEqual(AdoptionProtocol.paths.withLock { $0 }, ["/x/report/heartbeat/mobile"])
    }
}

private actor AdoptionReports {
    var values: [PlaybackWatchReport] = []
    func append(_ value: PlaybackWatchReport) { values.append(value) }
    func waitForCount(_ count: Int) async -> [PlaybackWatchReport] {
        for _ in 0..<200 { if values.count >= count { break }; try? await Task.sleep(for: .milliseconds(5)) }
        return values
    }
}

private final class AdoptionProtocol: URLProtocol, @unchecked Sendable {
    static let paths = Mutex<[String]>([])
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.paths.withLock { $0.append(request.url!.path) }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"code":0,"data":{"ts":321}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
