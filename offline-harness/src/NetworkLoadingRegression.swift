import Foundation
import Synchronization

/// 全部请求停在本地 URLProtocol；不读取/修改登录凭据，也不访问远端服务。
private final class NetworkFixture: URLProtocol, @unchecked Sendable {
    struct State {
        var body = Data(#"{"code":0,"message":"ok","data":{}}"#.utf8)
        var error: URLError?
        var requests: [URLRequest] = []
    }
    static let state = Mutex(State())
    static func reset(body: String = #"{"code":0,"message":"ok","data":{}}"#, error: URLError? = nil) {
        state.withLock { $0 = State(body: Data(body.utf8), error: error) }
    }
    static var requests: [URLRequest] { state.withLock { $0.requests } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (body, error) = Self.state.withLock {
            $0.requests.append(request)
            return ($0.body, $0.error)
        }
        if let error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
                                                                httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

@MainActor
private final class Gate<Value> {
    var pending: CheckedContinuation<Value, Never>?
    func value() async -> Value { await withCheckedContinuation { pending = $0 } }
    func resolve(_ value: Value) { pending?.resume(returning: value); pending = nil }
}

@MainActor
@main
struct NetworkLoadingRegression {
    private static var checks = 0
    private static func expect(_ value: Bool, _ label: String) {
        precondition(value, label)
        checks += 1
        print("PASS  \(label)")
    }
    private static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<1000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        preconditionFailure("Timed out waiting for fixture")
    }
    private static func defaults() -> UserDefaults { UserDefaults(suiteName: "NetworkLoadingRegression.\(UUID())")! }
    private static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NetworkFixture.self]
        return URLSession(configuration: config)
    }
    private static func video(_ id: Int) -> VideoSummary {
        VideoSummary(bvid: "BV\(id)", aid: id, cid: id, title: "video", pic: "", desc: "", duration: 1,
                     pubdate: 1, owner: VideoOwner(mid: 1, name: "owner", face: ""),
                     stat: VideoStat(view: 0, danmaku: 0, like: 0, favorite: 0, coin: 0, share: 0, reply: 0),
                     recommendationFeedback: RecommendationFeedbackOptions(goto: "av", param: id,
                         dislikeReasons: [reason], feedbacks: nil))
    }
    private static let reason = RecommendationFeedbackOptions.Reason(id: 17, name: "reason", toast: nil)
    private static let fixtureSessionID = UUID()
    private static let fixtureAccount = HomeFeedAccount(accountID: 42, hasAppCredential: true)

    static func main() async throws {
        Task.detached {
            try? await Task.sleep(for: .seconds(30))
            fatalError("Network regression watchdog")
        }
        try await requestSafety()
        try await signerSafety()
        await homeCancellation()
        await stagedRefresh()
        await feedbackSession()
        await delayedFeedbackDispatch()
        print("NETWORK LOADING: \(checks) checks passed")
    }

    private static func requestSafety() async throws {
        let id = UUID()
        let identity = DeviceIdentity.AuthenticatedRequestSnapshot(sessionID: id, accountID: 42,
            csrfToken: "fixture", cookieHeader: "SESSDATA=fixture", isLoggedIn: true)
        let session = session()
        defer { session.invalidateAndCancel() }
        let client = APIClient(session: session, authentication: { identity }, appAuthentication: {
            DeviceIdentity.AppRequestAccount(accessKey: "fixture", mid: 42, sessionID: id)
        })

        NetworkFixture.reset(body: #"{"code":-101,"message":"expired","data":"login required"}"#)
        do {
            let _: [String: Int] = try await client.get(path: "fixture")
            preconditionFailure("Expected API error")
        } catch BiliAPIError.apiError(let code, _) {
            expect(code == -101, "API preserves expired-session error despite heterogeneous data")
        }

        NetworkFixture.reset()
        do {
            try await client.post(path: "fixture", expectedSessionID: UUID())
            preconditionFailure("Expected stale-session cancellation")
        } catch is CancellationError {}
        expect(NetworkFixture.requests.isEmpty, "Stale queued write sends zero HTTP requests")
        try await client.post(path: "fixture", expectedSessionID: id)
        expect(NetworkFixture.requests.count == 1, "Current-session write sends exactly once")
        expect(NetworkFixture.requests[0].value(forHTTPHeaderField: "Cookie") == "SESSDATA=fixture",
               "Write uses the validated atomic Cookie snapshot")
        expect(!NetworkFixture.requests[0].httpShouldHandleCookies, "Write cannot merge shared Cookie jar")

        NetworkFixture.reset(error: URLError(.timedOut))
        do { try await client.post(path: "fixture", expectedSessionID: id) }
        catch let error as URLError { expect(error.code == .timedOut, "Write returns transport failure") }
        expect(NetworkFixture.requests.count == 1, "Timed-out POST is never retried")

        NetworkFixture.reset(error: URLError(.timedOut))
        do { let _: BiliEmptyData = try await client.getApp(path: "x/feed/dislike", params: [:], retries: 0) }
        catch let error as URLError { expect(error.code == .timedOut, "GET feedback returns transport failure") }
        expect(NetworkFixture.requests.count == 1, "GET-shaped feedback with retries disabled is sent once")
    }

    private static func signerSafety() async throws {
        let image = "7cd084941338484aae1ad9425b84077c"
        let sub = "4932caff0ff746eab6f01bf08b70ac45"
        expect(try WBISigner.makeMixinKey(imgKey: image, subKey: sub) == "ea1db124af3c7062474693fa704f4ff8",
               "WBI mixin preserves the reference permutation")
        for invalid in ["", "x", String(repeating: "é", count: 32), String(repeating: "g", count: 32)] {
            do {
                _ = try WBISigner.makeMixinKey(imgKey: invalid, subKey: sub)
                preconditionFailure("Malformed key must not index out of bounds")
            } catch BiliAPIError.missingWbiKeys {}
        }
        expect(true, "WBI rejects truncated and non-ASCII/non-hex keys without crashing")

        NetworkFixture.reset(body: "{\"code\":0,\"data\":{\"wbi_img\":{\"img_url\":\"https://i.example/\(image).png\",\"sub_url\":\"https://i.example/\(sub).png\"}}}")
        let session = session()
        defer { session.invalidateAndCancel() }
        let signer = WBISigner(session: session, defaults: defaults(), cookieHeader: { "fixture=1" })
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 { group.addTask { _ = try await signer.sign(params: ["key": "value"]) } }
            try await group.waitForAll()
        }
        expect(NetworkFixture.requests.count == 1, "20 concurrent WBI consumers share one nav request")
        expect(!NetworkFixture.requests[0].httpShouldHandleCookies, "WBI nav cannot reuse logged-out shared cookies")
    }

    private static func homeCancellation() async {
        let account = HomeFeedAccount(accountID: 42, hasAppCredential: true)
        let oldAccount = Gate<HomeFeedAccount>()
        var reads = 0
        var fetches = 0
        let model = HomeViewModel(defaults: defaults(), currentAccount: {
            reads += 1
            return reads == 1 ? await oldAccount.value() : account
        }, currentSessionID: { fixtureSessionID }, fetchRecommendations: { _ in fetches += 1; return [video(fetches)] })
        let oldLoad = Task { await model.loadInitial() }
        await waitUntil { oldAccount.pending != nil }
        await model.refresh()
        oldAccount.resolve(HomeFeedAccount(accountID: 7, hasAppCredential: true))
        await oldLoad.value
        expect(fetches == 1, "Replaced initial load never sends a stale feed request after account lookup")
        await model.refreshIfAccountChanged(to: account)
        expect(fetches == 1, "Late canceled lookup cannot overwrite the loaded-account marker")
    }

    private static func stagedRefresh() async {
        var requested: [Int] = []
        let model = HomeViewModel(defaults: defaults(), currentAccount: { fixtureAccount },
                                  currentSessionID: { fixtureSessionID }, fetchRecommendations: { index in
            requested.append(index)
            return [video(requested.count)]
        })
        await model.loadInitial()
        await model.refresh(staged: true)
        await model.loadReplacementPage()
        await model.loadMoreIfNeeded(current: model.videos[0])
        expect(requested == [0, 0], "Old cells cannot paginate while refresh waits for its exit animation")
        model.commitStagedRefresh()
        await model.loadReplacementPage()
        expect(requested == [0, 0, 1], "Pagination resumes from the refreshed cursor after commit")
        expect(model.videos.map(\.aid) == [2, 1, 3], "Staging preserves refresh order and one copy per video")
    }

    private static func feedbackSession() async {
        var session = UUID()
        let gate = Gate<Void>()
        var reports = 0
        let model = HomeViewModel(defaults: defaults(), reportUninterested: { _, _ in
            reports += 1
            await gate.value()
        }, currentAccount: { fixtureAccount }, currentSessionID: { session }, fetchRecommendations: { _ in [video(1)] })
        await model.loadInitial()
        let invalid = RecommendationFeedbackOptions.Reason(id: 999, name: "foreign", toast: nil)
        _ = await model.markUninterested(model.videos[0], reason: invalid)
        expect(reports == 0, "Unknown recommendation-feedback reason is never uploaded")
        let task = Task { await model.markUninterested(model.videos[0], reason: reason) }
        await waitUntil { gate.pending != nil }
        session = UUID()
        gate.resolve(())
        let message = await task.value
        expect(message == nil && model.videos.count == 1, "Old-session feedback cannot remove a new-session card or toast")
        expect(model.reportingIDs.isEmpty, "Feedback request state is released after session change")
    }

    private static func delayedFeedbackDispatch() async {
        for action in 0..<3 {
            NetworkFixture.reset()
            var currentSession = UUID()
            let newSession = UUID()
            let credentials = Gate<DeviceIdentity.AppRequestAccount>()
            let transport = session()
            defer { transport.invalidateAndCancel() }
            let client = APIClient(session: transport, appAuthentication: { await credentials.value() })
            // No reporter override: exercise Home -> the real BiliAPI wrapper ->
            // APIClient, with only the credential lookup/HTTP boundary injected.
            let model = HomeViewModel(defaults: defaults(), currentAccount: { fixtureAccount },
                currentSessionID: {
                    let clickedSession = currentSession
                    // Deterministically place the account change immediately
                    // after the click snapshot and before any reporter runs.
                    currentSession = newSession
                    return clickedSession
                }, feedbackClient: client,
                fetchRecommendations: { _ in [video(1)] })
            await model.loadInitial()
            let click = Task {
                switch action {
                case 0: return await model.markUninterested(model.videos[0], reason: reason)
                case 1: return await model.cancelUninterested(model.videos[0])
                default: return await model.dislikeWebRecommendation(model.videos[0], dislike: true)
                }
            }
            await waitUntil { credentials.pending != nil }
            // Even the reporter's first lookup now sees the new account.
            credentials.resolve(DeviceIdentity.AppRequestAccount(accessKey: "new-account-fixture", mid: 7,
                                                                   sessionID: newSession))
            let message = await click.value
            expect(NetworkFixture.requests.isEmpty, "Delayed feedback action \(action) cannot use a later login (zero requests)")
            expect(message == nil && model.videos.count == 1 && model.reportingIDs.isEmpty,
                   "Canceled feedback action \(action) preserves the card and clears busy state")
        }

        for action in 0..<3 {
            NetworkFixture.reset()
            let token = UUID()
            let transport = session()
            defer { transport.invalidateAndCancel() }
            let client = APIClient(session: transport, appAuthentication: {
                DeviceIdentity.AppRequestAccount(accessKey: "fixture", mid: 42, sessionID: token)
            })
            let model = HomeViewModel(defaults: defaults(), currentAccount: { fixtureAccount },
                currentSessionID: { token }, feedbackClient: client,
                fetchRecommendations: { _ in [video(1)] })
            await model.loadInitial()
            switch action {
            case 0: _ = await model.markUninterested(model.videos[0], reason: reason)
            case 1: _ = await model.cancelUninterested(model.videos[0])
            default: _ = await model.dislikeWebRecommendation(model.videos[0], dislike: true)
            }
            expect(NetworkFixture.requests.count == 1, "Valid feedback action \(action) still sends exactly once")
        }
    }
}
