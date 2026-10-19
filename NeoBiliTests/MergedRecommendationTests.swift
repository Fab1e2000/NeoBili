import XCTest
import Synchronization
@testable import NeoBili
@testable import NeoBiliData
@testable import NeoBiliDomain

final class MergedRecommendationTests: XCTestCase {
    func testAppFirstInterleaveDeduplicatesAndPreservesCardAttribution() throws {
        var webDuplicate = video(1); webDuplicate.isWebRecommendation = true
        let result = try MergedRecommendation.combine(request: .init(source: .merged),
            app: .success(.init(videos: [video(1), video(2)], nextRequest: .init(source: .app, pageIndex: 1, appCursor: 900))),
            web: .success(.init(videos: [webDuplicate, video(3), video(4)], nextRequest: .init(source: .web, pageIndex: 1))))
        XCTAssertEqual(result.videos.map(\.aid), [1, 2, 3, 4])
        XCTAssertFalse(result.videos[0].isWebRecommendation)
        let next = try XCTUnwrap(result.nextRequest)
        XCTAssertEqual(next.source, .merged)
        XCTAssertEqual(next.appCursor, 900)
        XCTAssertEqual(next.appPageIndex, 1)
        XCTAssertEqual(next.webPageIndex, 1)
    }

    func testFailedSideKeepsItsPositionWhileSuccessfulSideAdvances() throws {
        var request = RecommendationRequest(source: .merged, pageIndex: 3, appCursor: 777)
        request.appPageIndex = 2; request.webPageIndex = 3
        let result = try MergedRecommendation.combine(request: request,
            app: .failure(URLError(.timedOut)),
            web: .success(.init(videos: [video(4)], nextRequest: .init(source: .web, pageIndex: 4))))
        let next = try XCTUnwrap(result.nextRequest)
        XCTAssertEqual(next.appCursor, 777)
        XCTAssertEqual(next.appPageIndex, 2)
        XCTAssertFalse(next.appFinished)
        XCTAssertEqual(next.webPageIndex, 4)
    }

    func testFinishedSideDoesNotStopOtherSideAndBothFinishedStop() throws {
        let empty = RecommendationBatch(videos: [], nextRequest: nil)
        let first = try MergedRecommendation.combine(request: .init(source: .merged), app: .success(empty),
            web: .success(.init(videos: [], nextRequest: .init(source: .web, pageIndex: 1))))
        let next = try XCTUnwrap(first.nextRequest)
        XCTAssertTrue(next.appFinished)
        XCTAssertFalse(next.webFinished)
        XCTAssertEqual(next.webPageIndex, 1, "Filtered pages must still advance")
        XCTAssertNil(try MergedRecommendation.combine(request: next, app: .success(empty), web: .success(empty)).nextRequest)
    }

    func testCancellationAndTotalFailureAreNotHiddenByMerge() {
        let good = RecommendationBatch(videos: [video(1)], nextRequest: nil)
        XCTAssertThrowsError(try MergedRecommendation.combine(request: .init(source: .merged),
            app: .failure(CancellationError()), web: .success(good)))
        XCTAssertThrowsError(try MergedRecommendation.combine(request: .init(source: .merged),
            app: .failure(URLError(.timedOut)), web: .failure(URLError(.notConnectedToInternet))))
    }

    func testBiliPaiWebProfilesAndLegacyPreferenceMigration() {
        let web = WebRecommendationPage.parameters(freshIndex: 3, timestampMilliseconds: 123456)
        XCTAssertEqual(web, ["ps":"20", "fresh_type":"3", "fresh_idx":"3", "feed_version":"123456", "y_num":"3"])
        let merged = WebRecommendationPage.parameters(freshIndex: 3, merged: true)
        XCTAssertEqual(merged["fresh_type"], "4")
        XCTAssertEqual(merged["feed_version"], "V8")
        XCTAssertEqual(merged["brush"], "3")
        XCTAssertNil(merged["y_num"])
        XCTAssertEqual(RecommendationRequest.savedSource(rawValue: nil, legacyUsesApp: nil), .app)
        XCTAssertEqual(RecommendationRequest.savedSource(rawValue: nil, legacyUsesApp: false), .web)
        XCTAssertEqual(RecommendationRequest.savedSource(rawValue: "merged", legacyUsesApp: false), .merged)
        XCTAssertEqual(RecommendationRequest.savedSource(rawValue: "bad", legacyUsesApp: true), .app)
    }

    @MainActor
    func testSourceRemainsFixedUntilNewLaunchSnapshot() async throws {
        let suite = "feed-source-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var sources: [RecommendationRequest.Source] = []
        let model = HomeViewModel(defaults: defaults, fetchRecommendations: { request in
            sources.append(request.source)
            return .init(videos: [], nextRequest: nil)
        })
        await model.loadInitial()
        defaults.set("merged", forKey: RecommendationRequest.sourceKey)
        await model.refresh()
        XCTAssertEqual(sources, [.app, .app])
        let relaunched = HomeViewModel(defaults: defaults, fetchRecommendations: { request in
            sources.append(request.source)
            return .init(videos: [], nextRequest: nil)
        })
        await relaunched.loadInitial()
        XCTAssertEqual(sources, [.app, .app, .merged])
    }

    func testMergedTransportKeepsCookieAndAppAuthenticationSeparate() async throws {
        let identity = TestNetworking.identity()
        await identity.setLoginCookies(sessdata: "fixture-cookie", biliJct: "fixture-csrf", dedeUserID: "42")
        await identity.setAccessKey("fixture-key")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MergedFeedProtocol.self]
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        MergedFeedProtocol.requests.withLock { $0 = [] }
        let client = TestNetworking.client(identity: identity, session: session, signWebParameters: { $0 })
        let service = RecommendationService.live(client: client, identity: identity,
            session: AppRecommendationSession(), network: AppNetworkMetadata(monitoring: false),
            clickReporter: RecommendationClickReporter(identity: identity, client: client), filter: { .none })
        let batch = try await service.recommendFeed(request: .init(source: .merged))
        XCTAssertEqual(batch.nextRequest?.appCursor, 900)
        XCTAssertEqual(batch.nextRequest?.webPageIndex, 1)
        let requests = MergedFeedProtocol.requests.withLock { $0 }
        XCTAssertEqual(requests.count, 2)
        let app = try XCTUnwrap(requests.first { $0.url?.host == "app.bilibili.com" })
        let web = try XCTUnwrap(requests.first { $0.url?.host == "api.bilibili.com" })
        XCTAssertNil(app.value(forHTTPHeaderField: "Cookie"))
        XCTAssertFalse(app.httpShouldHandleCookies)
        XCTAssertTrue(web.value(forHTTPHeaderField: "Cookie")?.contains("fixture-cookie") == true)
        func params(_ request: URLRequest) -> [String: String] {
            Dictionary(uniqueKeysWithValues: URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
        }
        XCTAssertEqual(params(app)["access_key"], "fixture-key")
        XCTAssertEqual(params(app)["mobi_app"], AppClientIdentity.mobiApp)
        XCTAssertEqual(params(web)["fresh_type"], "4")
        XCTAssertNil(params(web)["access_key"])
    }

    func testWebRequestRejectsStaleAccountBeforeSending() async throws {
        let identity = TestNetworking.identity()
        let client = TestNetworking.client(identity: identity, signWebParameters: { $0 })
        do {
            let _: WebRecommendationPage = try await client.get(path: "x/web-interface/wbi/index/top/feed/rcmd",
                expectedSessionID: UUID())
            XCTFail("Stale session must be rejected")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }

    private func video(_ aid: Int) -> VideoSummary {
        VideoSummary(bvid: "BV\(aid)", aid: aid, cid: aid, title: "Video \(aid)", pic: "", desc: "", duration: 20,
            pubdate: 0, owner: .init(mid: 1, name: "UP", face: ""),
            stat: .init(view: 1, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0))
    }
}

private final class MergedFeedProtocol: URLProtocol, @unchecked Sendable {
    static let requests = Mutex<[URLRequest]>([])
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.withLock { $0.append(request) }
        let body = request.url?.host == "app.bilibili.com"
            ? #"{"code":0,"data":{"items":[{"idx":900,"card_goto":"unsupported"}]}}"#
            : #"{"code":0,"data":{"item":[{"goto":"unsupported"}]}}"#
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
