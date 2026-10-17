import XCTest
import Synchronization
@testable import NeoBili

@MainActor
final class AppProtocolIntegrationTests: XCTestCase {
    private let login = UUID()

    private func context(key: String? = "fixture-access") -> AppRequestContext {
        .init(account: .init(accessKey: key, mid: 42, sessionID: login),
              headers: ["buvid": "fixture-device", "session_id": "12345678", "Referer": "https://example.test/"])
    }

    func testSignedQueryMatchesIndependentGoldenBytesIncludingEmptyAndUnicode() throws {
        let request = try AppRequestEncoder(timestamp: { 1_700_000_000 }).encode(
            .get(path: "x/v2/feed/index", parameters: ["q": "A+B & 测试", "empty": ""], requiresAccountCredential: true),
            context: context())
        XCTAssertEqual(request.url?.absoluteString,
            "https://app.bilibili.com/x/v2/feed/index?access_key=fixture-access&appkey=27eb53fc9058f8c3&empty=&q=A%2BB%20%26%20%E6%B5%8B%E8%AF%95&sign=8df05bb434a5daa7bd271a1b2aadfe76&ts=1700000000")
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-bili-mid"), "42")
        XCTAssertEqual(request.value(forHTTPHeaderField: "buvid"), "fixture-device")
        XCTAssertNil(request.value(forHTTPHeaderField: "Referer"))
    }

    func testFormUsesSameGoldenSignedBytesAndAPIHostWithoutBrowserAuthentication() throws {
        let request = try AppRequestEncoder(timestamp: { 1_700_000_000 }).encode(
            .form(path: "x/report/heartbeat/mobile", parameters: ["q": "A+B & 测试", "empty": ""], usesAPIHost: true),
            context: context())
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.bilibili.com/x/report/heartbeat/mobile")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.httpBody, Data("access_key=fixture-access&appkey=27eb53fc9058f8c3&empty=&q=A%2BB%20%26%20%E6%B5%8B%E8%AF%95&sign=8df05bb434a5daa7bd271a1b2aadfe76&ts=1700000000".utf8))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
    }

    func testGRPCMetadataUsesCapturedAccountAndDeviceAndFramesRawPayload() throws {
        let payload = Data([8, 1])
        let request = try AppRequestEncoder().encode(.grpc(path: "fixture.Service/View", payload: payload), context: context())
        XCTAssertEqual(request.url?.absoluteString, "https://grpc.biliapi.net/fixture.Service/View")
        XCTAssertEqual(request.httpBody, Data([0, 0, 0, 0, 2, 8, 1]))
        XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "identify_v1 fixture-access")
        let metadata = try AppProto(XCTUnwrap(Data(base64Encoded: XCTUnwrap(request.value(forHTTPHeaderField: "x-bili-metadata-bin")))))
        XCTAssertEqual(metadata.text(1), "fixture-access")
        XCTAssertEqual(metadata.text(2), "iphone_i")
        XCTAssertEqual(metadata.number(4), 91_300_300)
        XCTAssertEqual(metadata.text(6), "fixture-device")
        XCTAssertEqual(metadata.text(7), "ios")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
    }

    func testLogTransportDoesNotAttachAccessKeyAndKeepsOpaqueBody() throws {
        let body = Data([31, 139, 8, 0])
        var context = context()
        context.headers["Neuron-Events"] = "999"
        let request = try AppRequestEncoder().encode(.unrealtimeLog(body: body, eventCount: 1), context: context)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Neuron-Events"), "1")
        XCTAssertEqual(request.url?.absoluteString, "https://dataflow.biliapi.com/log/pbmobile/unrealtime?ios")
        XCTAssertEqual(request.httpBody, body)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Encoding"), "gzip")
        XCTAssertEqual(request.value(forHTTPHeaderField: "app-key"), "iphone_i")
        XCTAssertNil(request.value(forHTTPHeaderField: "authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
    }

    func testReplacingCodecLeavesAuthenticationTransportAndResponseDecodingIntact() async throws {
        let probe = CodecProbe()
        let session = transport()
        defer { session.invalidateAndCancel() }
        let account = context().account
        let client = APIClient(session: session, appEncoder: FixtureCodec(probe: probe), appAuthentication: { account })
        let result: Payload = try await client.getApp(path: "fixture", params: [:], headers: ["buvid": "own-device"],
            expectedSessionID: login, requiresAccountCredential: true)
        XCTAssertEqual(result.value, 7)
        XCTAssertEqual(probe.contexts.withLock { $0.first?.account.sessionID }, login)
        XCTAssertEqual(probe.contexts.withLock { $0.first?.headers["buvid"] }, "own-device")
        XCTAssertEqual(ProtocolTransport.state.withLock { $0.requests.first?.value(forHTTPHeaderField: "X-Fixture-Codec") }, "used")
    }

    func testStaleSessionAndMissingCredentialAreRejectedBeforeInjectedCodecOrTransport() async throws {
        let probe = CodecProbe()
        let session = transport()
        defer { session.invalidateAndCancel() }
        let account = context().account
        let client = APIClient(session: session, appEncoder: FixtureCodec(probe: probe), appAuthentication: { account })
        do {
            let _: Payload = try await client.getApp(path: "fixture", params: [:], expectedSessionID: UUID())
            XCTFail("Old session must not encode a request with new credentials")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        let missing = context(key: nil).account
        let noKey = APIClient(session: session, appEncoder: FixtureCodec(probe: probe), appAuthentication: { missing })
        do {
            try await noKey.postApp(path: "fixture", expectedSessionID: login)
            XCTFail("Codec substitution must not bypass authentication")
        } catch BiliAPIError.missingAccessKey {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(probe.contexts.withLock { $0.isEmpty })
        XCTAssertTrue(ProtocolTransport.state.withLock { $0.requests.isEmpty })
    }

    func testCommonAppIdentityReachesFeedbackWithoutCallerHeaders() async throws {
        let session = transport()
        defer { session.invalidateAndCancel() }
        let account = context().account
        let client = APIClient(session: session, appAuthentication: { account }, appHeaders: { sessionID in
            XCTAssertEqual(sessionID, account.sessionID)
            return ["buvid": "own-device", "GuestId": "123", "x-bili-ticket": "fixture-ticket"]
        })
        let _: Payload = try await client.getApp(path: "x/feed/dislike", params: [:], retries: 0,
                                                expectedSessionID: login)
        let sent = try XCTUnwrap(ProtocolTransport.state.withLock { $0.requests.first })
        XCTAssertEqual(sent.value(forHTTPHeaderField: "buvid"), "own-device")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "guestid"), "123")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "x-bili-ticket"), "fixture-ticket")
    }

    func testAccountChangeDuringHeaderPreparationStopsRequest() async throws {
        let session = transport()
        defer { session.invalidateAndCancel() }
        let initial = context().account
        let current = Mutex(initial)
        let client = APIClient(session: session, appAuthentication: { current.withLock { $0 } }, appHeaders: { _ in
            current.withLock { $0 = .init(accessKey: "new-account", mid: 84, sessionID: UUID()) }
            return ["guestid": "123"]
        })
        do {
            let _: Payload = try await client.getApp(path: "fixture", params: [:], expectedSessionID: login)
            XCTFail("A request prepared for the old account must not be sent")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(ProtocolTransport.state.withLock { $0.requests.isEmpty })
    }

    func testAccountChangeBeforeResponseRejectsOldAppData() async throws {
        let session = transport()
        defer { session.invalidateAndCancel() }
        let initial = context().account
        let current = Mutex(initial)
        ProtocolTransport.state.withLock {
            $0.beforeResponse = {
                current.withLock { $0 = .init(accessKey: "other-fixture", mid: 84, sessionID: UUID()) }
            }
        }
        let client = APIClient(session: session, appAuthentication: { current.withLock { $0 } },
                               appHeaders: { _ in [:] })
        do {
            let _: Payload = try await client.getApp(path: "fixture", params: [:], retries: 0,
                                                     expectedSessionID: initial.sessionID)
            XCTFail("A response belonging to the old account must be rejected")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(ProtocolTransport.state.withLock { $0.requests.count }, 1)
    }

    func testWebFormPreservesLiteralPlusAndUnicode() async throws {
        let session = transport()
        defer { session.invalidateAndCancel() }
        let generation = UUID()
        let client = APIClient(session: session, authentication: {
            .init(sessionID: generation, accountID: 42, csrfToken: "fixture",
                  cookieHeader: "SESSDATA=fixture", isLoggedIn: true)
        })
        let message = "C++ & A=B 中文 %"
        try await client.post(path: "fixture", form: ["message": message])
        let request = try XCTUnwrap(ProtocolTransport.state.withLock { $0.requests.first })
        let data = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(String(data: data, encoding: .utf8))
        let field = try XCTUnwrap(body.split(separator: "&").first { $0.hasPrefix("message=") })
        let value = String(field.dropFirst("message=".count))
            .replacingOccurrences(of: "+", with: " ").removingPercentEncoding
        XCTAssertEqual(value, message)
    }

    func testReadRetriesReuseEncodedRequestWhileBehavioralWriteIsNotRetried() async throws {
        let session = transport()
        defer { session.invalidateAndCancel() }
        let account = context().account
        let client = APIClient(session: session, appEncoder: AppRequestEncoder(timestamp: { 1_700_000_000 }),
                               appAuthentication: { account })
        ProtocolTransport.state.withLock { $0.failuresRemaining = 1 }
        let _: Payload = try await client.getApp(path: "fixture", params: [:], retries: 1, expectedSessionID: login)
        let requests = ProtocolTransport.state.withLock { $0.requests }
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.first?.url, requests.last?.url, "Retry reuses the captured credentials and signature")
        ProtocolTransport.state.withLock { $0 = .init(failuresRemaining: 2) }
        do {
            try await client.postApp(path: "fixture", expectedSessionID: login)
            XCTFail("Expected the synthetic connection failure")
        } catch let error as URLError { XCTAssertEqual(error.code, .cannotConnectToHost) }
        XCTAssertEqual(ProtocolTransport.state.withLock { $0.requests.count }, 1)
    }

    func testWatchEncodingUsesMeasuredTimeAndSuppliedDeviceTimestamp() {
        let report = PlaybackWatchReport(position: -1, watchedTime: 120.7, pausedTime: 5.3,
            maximumPosition: 450, duration: 450.9, startTimestamp: 123, sourceFields: ["track_id": "own-track"])
        let mobile = AppWatchProtocol.mobileParameters(report)
        XCTAssertEqual(mobile["played_time"], "120", "Resumed position is not watched time")
        XCTAssertEqual(mobile["last_play_progress_time"], "450")
        XCTAssertEqual(mobile["track_id"], "own-track")
        let history = AppWatchProtocol.historyParameters(aid: 1, cid: 2, report: report, deviceTimestamp: 456)
        XCTAssertEqual(history["progress"], "-1")
        XCTAssertEqual(history["device_ts"], "456")
        XCTAssertEqual(history["duration"], "450")
    }

    private func transport() -> URLSession {
        ProtocolTransport.state.withLock { $0 = .init() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProtocolTransport.self]
        return URLSession(configuration: configuration)
    }
    private struct Payload: Decodable { let value: Int }
}

private final class CodecProbe: Sendable {
    let contexts = Mutex<[AppRequestContext]>([])
}
private struct FixtureCodec: AppRequestEncoding {
    let probe: CodecProbe
    func encode(_ operation: AppRequest, context: AppRequestContext) throws -> URLRequest {
        probe.contexts.withLock { $0.append(context) }
        var request = URLRequest(url: URL(string: "https://example.test/encoded")!)
        request.setValue("used", forHTTPHeaderField: "X-Fixture-Codec")
        return request
    }
}
private final class ProtocolTransport: URLProtocol, @unchecked Sendable {
    struct State { var failuresRemaining = 0; var requests: [URLRequest] = []; var beforeResponse: (@Sendable () -> Void)? }
    static let state = Mutex(State())
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                bytes.append(contentsOf: buffer.prefix(count))
            }
            captured.httpBody = bytes
        }
        let fail = Self.state.withLock {
            $0.requests.append(captured)
            if $0.failuresRemaining > 0 { $0.failuresRemaining -= 1; return true }
            return false
        }
        if fail { client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost)); return }
        Self.state.withLock { $0.beforeResponse }?()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"code":0,"data":{"value":7}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
