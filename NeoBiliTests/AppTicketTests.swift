import XCTest
import Synchronization
@testable import NeoBili

final class AppTicketTests: XCTestCase {
    private let headers = ["buvid": "fake-device", "x-bili-device-bin": Data([8, 1]).base64EncodedString()]
    private func response(_ ticket: String = "fixture-ticket", ttl: Int = 7200) -> (Data, URLResponse) {
        (AppProto.frame(AppProto.string(1, ticket) + AppProto.integer(2, 1) + AppProto.integer(3, ttl)),
         HTTPURLResponse(url: URL(string: "https://grpc.biliapi.net")!, statusCode: 200, httpVersion: nil, headerFields: ["grpc-status": "0"])!)
    }

    func testSigningSortsContextAndProducesKnownHMAC() throws {
        let input = AppTicketProtocol.signingInput(device: Data("d".utf8), context: ["z": Data(), "b": Data("2".utf8), "a": Data("1".utf8), "": Data("ignored".utf8)])
        XCTAssertEqual(String(data: input, encoding: .utf8), "da1b2z")
        let digest = AppTicketProtocol.signature(device: Data("The quick brown fox jumps over the lazy dog".utf8), key: Data("key".utf8))
        XCTAssertEqual(digest.map { String(format: "%02x", $0) }.joined(), "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8")
        let request = try AppTicketProtocol.request(headers: headers, accessKey: "fake-access")
        let message = try AppProto(AppProto.unframe(XCTUnwrap(request.httpBody)))
        XCTAssertEqual(message.text(2), "ec01")
        XCTAssertEqual(message.data(3)?.count, 32)
        XCTAssertNil(message.text(4))
        XCTAssertEqual(request.value(forHTTPHeaderField: "authorization"), "identify_v1 fake-access")
        XCTAssertThrowsError(try AppTicketProtocol.request(headers: [:], accessKey: nil))
    }

    func testCachedGetterReturnsImmediatelyAndRenewsBeforeExpiry() async {
        let now = Mutex<TimeInterval>(1000), count = Mutex(0)
        let reply = response()
        let store = CredentialStorage.memory()
        let service = AppTicketService(credentials: store, transport: { _ in count.withLock { $0 += 1 }; return reply }, clock: { now.withLock { $0 } }, jitter: { 0 })
        let initial = await service.cachedTicket(scope: "a", headers: headers, accessKey: nil)
        XCTAssertNil(initial)
        await service.awaitPendingForTesting()
        let first = await service.cachedTicket(scope: "a", headers: headers, accessKey: nil)
        XCTAssertEqual(first, "fixture-ticket")
        XCTAssertEqual(count.withLock { $0 }, 1)
        now.withLock { $0 = 6400 } // Exactly 1800 remains: no refresh.
        _ = await service.cachedTicket(scope: "a", headers: headers, accessKey: nil)
        await service.awaitPendingForTesting()
        XCTAssertEqual(count.withLock { $0 }, 1)
        now.withLock { $0 += 1 }
        let renewing = await service.cachedTicket(scope: "a", headers: headers, accessKey: nil)
        XCTAssertEqual(renewing, "fixture-ticket")
        await service.awaitPendingForTesting()
        XCTAssertEqual(count.withLock { $0 }, 2)
        let restored = AppTicketService(credentials: store, transport: { _ in XCTFail("Valid cache should not load"); return reply }, clock: { now.withLock { $0 } })
        let persisted = await restored.cachedTicket(scope: "a", headers: headers, accessKey: nil)
        XCTAssertEqual(persisted, "fixture-ticket")
    }

    func testExactStatusInvalidatesFailureKeepsTicketAndHasBoundedRetry() async {
        let now = Mutex<TimeInterval>(1000), count = Mutex(0)
        let reply = response()
        let service = AppTicketService(credentials: .memory(), transport: { _ in
            let calls = count.withLock { $0 += 1; return $0 }
            if calls > 1 { throw URLError(.notConnectedToInternet) }
            return reply
        }, clock: { now.withLock { $0 } }, jitter: { 0 })
        _ = await service.cachedTicket(scope: "a", headers: headers, accessKey: nil)
        await service.awaitPendingForTesting()
        await service.observe(status: "01", scope: "a")
        await service.observe(status: "1", scope: "other")
        XCTAssertEqual(count.withLock { $0 }, 1)
        await service.observe(status: "1", scope: "a")
        await service.awaitPendingForTesting()
        let stale = await service.cachedTicket(scope: "a", headers: headers, accessKey: nil)
        XCTAssertEqual(stale, "fixture-ticket")
        XCTAssertEqual(count.withLock { $0 }, 2)
        now.withLock { $0 += 1 }
        _ = await service.cachedTicket(scope: "a", headers: headers, accessKey: nil)
        await service.awaitPendingForTesting()
        XCTAssertEqual(count.withLock { $0 }, 3)
    }

    func testAccountSwitchDoesNotReturnPreviousTicket() async {
        let reply = response()
        let service = AppTicketService(credentials: .memory(), transport: { _ in reply })
        _ = await service.cachedTicket(scope: "a", headers: headers, accessKey: nil)
        await service.awaitPendingForTesting()
        await service.reset(scope: "b")
        let next = await service.cachedTicket(scope: "b", headers: headers, accessKey: nil)
        XCTAssertNil(next)
        await service.awaitPendingForTesting()
    }

    func testLateCompletionCannotOverwriteNewAccountCache() async {
        let gate = TicketTestGate()
        let reply = response("old-account-ticket")
        let fresh = response("new-account-ticket")
        let service = AppTicketService(credentials: .memory(), transport: { request in
            if request.value(forHTTPHeaderField: "authorization") == "identify_v1 old" {
                await gate.wait()
                return reply // Deliberately ignores task cancellation.
            }
            return fresh
        })
        _ = await service.cachedTicket(scope: "a", headers: headers, accessKey: "old")
        while !(await gate.started) { await Task.yield() }
        await service.reset(scope: "b")
        _ = await service.cachedTicket(scope: "b", headers: headers, accessKey: "new")
        await service.awaitPendingForTesting()
        await gate.release()
        for _ in 0..<20 { await Task.yield() }
        let current = await service.cachedTicket(scope: "b", headers: headers, accessKey: "new")
        XCTAssertEqual(current, "new-account-ticket")
        await service.observe(status: "1", sentTicket: "old-account-ticket")
        let retained = await service.cachedTicket(scope: "b", headers: headers, accessKey: "new")
        XCTAssertEqual(retained, "new-account-ticket")
    }

    func testAccountInvalidationDropsPendingSuccessAndRejectsOldResponse() async {
        let gate = TicketTestGate()
        let calls = Mutex(0)
        let storage = CredentialStorage.memory()
        let reply = response("invalidated-account-ticket")
        let returned = expectation(description: "Cancelled transport still returns its old response")
        let service = AppTicketService(credentials: storage, transport: { _ in
            calls.withLock { $0 += 1 }
            await gate.wait() // The injected transport deliberately ignores cancellation.
            returned.fulfill()
            return reply
        })
        _ = await service.cachedTicket(scope: "old-epoch:device", headers: headers, accessKey: "old")
        while !(await gate.started) { await Task.yield() }
        await service.invalidateAccount(prefix: "old-epoch")
        await gate.release()
        await fulfillment(of: [returned], timeout: 2)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(storage.read("neobili.app.ticket"), "Late success must not repopulate invalidated credentials")

        // Cover both the scope-based hook and the sent-ticket hook before any new
        // account request supplies context. Neither may restart the old RPC.
        await service.observe(status: "1", scope: "old-epoch:device")
        await service.observe(status: "1", sentTicket: "invalidated-account-ticket")
        await service.observe(status: "1", sentTicket: nil)
        await service.awaitPendingForTesting()
        XCTAssertEqual(calls.withLock { $0 }, 1)
        XCTAssertNil(storage.read("neobili.app.ticket"))
    }

    func testRejectsMalformedAndErrorResponse() throws {
        let (data, response) = response()
        XCTAssertEqual(try AppTicketProtocol.response(data, response: response).ttl, 7200)
        XCTAssertThrowsError(try AppTicketProtocol.response(Data(), response: response))
        let denied = HTTPURLResponse(url: response.url!, statusCode: 200, httpVersion: nil, headerFields: ["grpc-status": "16"])!
        XCTAssertThrowsError(try AppTicketProtocol.response(data, response: denied))
    }
}

private actor TicketTestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var started = false
    func wait() async {
        started = true
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}
