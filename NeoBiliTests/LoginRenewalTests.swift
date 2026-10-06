import XCTest
import Synchronization
@testable import NeoBili

final class LoginRenewalTests: XCTestCase {
    private let device = AppLoginRenewal.Device(buvid: "test-tracking", localID: "test-local",
        deviceID: "test-server", name: "iPhone", platform: "fixture", headers: ["buvid": "test-tracking"])
    private func login(_ suffix: String = "old", mid: String = "42") -> SMSPassport.Credentials {
        .init(cookies: .init(sessdata: "cookie-" + suffix, biliJct: "csrf-" + suffix, dedeUserID: mid),
              accessKey: "access-" + suffix, refreshToken: "refresh-" + suffix, expiresIn: 3600)
    }
    private func identity(_ storage: CredentialStorage = .memory()) -> DeviceIdentity {
        DeviceIdentity(defaults: UserDefaults(suiteName: "RenewalTests." + UUID().uuidString)!,
                       credentials: storage, allowsNetwork: false, purgeCookies: {})
    }
    private func response(_ request: URLRequest, _ body: [String: Any]) throws -> (Data, URLResponse) {
        (try JSONSerialization.data(withJSONObject: body), HTTPURLResponse(url: request.url!, statusCode: 200,
             httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
    }
    private func fields(_ request: URLRequest) -> [String: String] {
        let encoded = request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
            ?? URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.percentEncodedQuery ?? ""
        return Dictionary(uniqueKeysWithValues: URLComponents(string: "https://example.test/?" + encoded)!.queryItems!.map { ($0.name, $0.value ?? "") })
    }
    private func refreshed(_ value: SMSPassport.Credentials) -> [String: Any] {
        ["code": 0, "data": ["token_info": ["mid": Int(value.cookies.dedeUserID)!,
            "access_token": value.accessKey, "refresh_token": value.refreshToken!, "expires_in": value.expiresIn!],
            "cookie_info": ["cookies": [["name":"SESSDATA","value":value.cookies.sessdata],
                ["name":"bili_jct","value":value.cookies.biliJct], ["name":"DedeUserID","value":value.cookies.dedeUserID]]]]]
    }

    func testRenewalOrdersRequestsAndConfirmsOldCredentialsAfterAtomicCommit() async throws {
        let storage = CredentialStorage.memory(), identity = identity(storage), old = login(), new = login("new")
        try await identity.saveSMSLogin(old, expectedSessionID: identity.loginSessionID, authorizationOnly: false)
        let session = identity.loginSessionID
        let paths = Mutex<[String]>([])
        await identity.renewLoginIfNeeded(transport: { request in
            let path = request.url!.lastPathComponent
            paths.withLock { $0.append(path) }
            XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            let form = self.fields(request)
            XCTAssertEqual(form["access_key"], old.accessKey)
            XCTAssertEqual(form["bili_local_id"], "test-local")
            XCTAssertEqual(form["device_id"], "test-server")
            switch path {
            case "info": return try self.response(request, ["code":0,"data":["mid":42,"expires_in":20,"refresh":true]])
            case "timestamp": return try self.response(request, ["code":0,"data":["timestamp":123]])
            case "refresh_token":
                XCTAssertEqual(form["sts"], "123")
                XCTAssertEqual(form["refresh_token"], old.refreshToken)
                return try self.response(request, self.refreshed(new))
            default:
                let current = await identity.appAccount()
                XCTAssertEqual(current.accessKey, new.accessKey)
                XCTAssertEqual(form["session"], old.cookies.sessdata)
                XCTAssertEqual(form["revoke_api"], "REFRESH_CONFIRM_REVOKE")
                return try self.response(request, ["code":0])
            }
        }, now: 100, device: device)
        XCTAssertEqual(paths.withLock { $0 }, ["info","timestamp","refresh_token","refresh"])
        XCTAssertEqual(identity.loginSessionID, session, "Renewal must not invalidate current playback")
        let beforeRestore = try await identity.appDeviceSnapshot(expectedSessionID: session)
        // Simulate an interruption between the atomic commit and legacy mirrors.
        storage.write("stale", "neobili.telemetry.loginEpoch")
        storage.write("stale", "neobili.access_key")
        let restored = self.identity(storage)
        let restoredDevice = try await restored.appDeviceSnapshot(expectedSessionID: restored.loginSessionID)
        XCTAssertEqual(restoredDevice.accountEpoch, beforeRestore.accountEpoch)
        let restoredAccount = await restored.appAccount()
        let restoredCookies = await restored.loginCookies()
        XCTAssertEqual(restoredAccount.accessKey, new.accessKey)
        XCTAssertEqual(restoredCookies, new.cookies)
        await identity.clearLoginCookies()
        let loggedOut = self.identity(storage)
        let empty = await loggedOut.accountSnapshot()
        XCTAssertFalse(empty.hasCredentials)
    }

    func testNoRefreshDoesNotRotateAndActivationIsThrottled() async throws {
        let identity = identity(), old = login(), count = Mutex(0)
        try await identity.saveSMSLogin(old, expectedSessionID: identity.loginSessionID, authorizationOnly: false)
        let transport: AppLoginRenewal.Transport = { request in
            count.withLock { $0 += 1 }
            return try self.response(request, ["code":0,"data":["mid":42,"expires_in":3600,"refresh":false]])
        }
        await identity.renewLoginIfNeeded(transport: transport, now: 100, device: device)
        await identity.renewLoginIfNeeded(transport: transport, now: 101, device: device)
        XCTAssertEqual(count.withLock { $0 }, 1)
        let account = await identity.appAccount()
        XCTAssertEqual(account.accessKey, old.accessKey)
    }

    func testOfflineBackoffAndLegacyLoginNeverInventRefreshToken() async throws {
        let identity = identity(), count = Mutex(0)
        await identity.saveLogin(login().cookies, accessKey: login().accessKey)
        let transport: AppLoginRenewal.Transport = { _ in count.withLock { $0 += 1 }; throw URLError(.notConnectedToInternet) }
        await identity.renewLoginIfNeeded(transport: transport, now: 1, device: device)
        XCTAssertEqual(count.withLock { $0 }, 0)
        try await identity.saveSMSLogin(login(), expectedSessionID: identity.loginSessionID, authorizationOnly: false)
        for time in [100.0, 101, 130, 159] { await identity.renewLoginIfNeeded(transport: transport, now: time, device: device) }
        XCTAssertEqual(count.withLock { $0 }, 1)
        await identity.renewLoginIfNeeded(transport: transport, now: 160, device: device)
        XCTAssertEqual(count.withLock { $0 }, 2)
        let account = await identity.appAccount()
        XCTAssertEqual(account.accessKey, login().accessKey)
    }

    func testReloginDuringRefreshRejectsLateOldResponse() async throws {
        let identity = identity(), old = login(), replacement = login("replacement")
        try await identity.saveSMSLogin(old, expectedSessionID: identity.loginSessionID, authorizationOnly: false)
        let confirmed = Mutex(false)
        await identity.renewLoginIfNeeded(transport: { request in
            switch request.url!.lastPathComponent {
            case "info": return try self.response(request, ["code":0,"data":["mid":42,"expires_in":20,"refresh":true]])
            case "timestamp": return try self.response(request, ["code":0,"data":["timestamp":123]])
            case "refresh_token":
                try await identity.saveSMSLogin(replacement, expectedSessionID: identity.loginSessionID, authorizationOnly: false)
                return try self.response(request, self.refreshed(self.login("late")))
            default: confirmed.withLock { $0 = true }; return try self.response(request, ["code":0])
            }
        }, now: 100, device: device)
        let account = await identity.appAccount()
        XCTAssertEqual(account.accessKey, replacement.accessKey)
        XCTAssertFalse(confirmed.withLock { $0 })
    }

    func testConfirmFailureNeverRollsBackAndTimestampFailureUsesMinusOne() async throws {
        let identity = identity(), old = login(), new = login("new")
        try await identity.saveSMSLogin(old, expectedSessionID: identity.loginSessionID, authorizationOnly: false)
        await identity.renewLoginIfNeeded(transport: { request in
            switch request.url!.lastPathComponent {
            case "info": return try self.response(request, ["code":0,"data":["mid":42,"expires_in":20,"refresh":true]])
            case "timestamp": throw URLError(.timedOut)
            case "refresh_token":
                XCTAssertEqual(self.fields(request)["sts"], "-1")
                return try self.response(request, self.refreshed(new))
            default: throw URLError(.timedOut)
            }
        }, now: 100, device: device)
        let account = await identity.appAccount(), state = await identity.renewalState
        XCTAssertEqual(account.accessKey, new.accessKey)
        XCTAssertEqual(state, "renewed-confirm-failed")
    }

    func testWrongAccountAndStorageFailureNeverConfirm() async throws {
        for failStorage in [false, true] {
            let base = CredentialStorage.memory(), reject = Mutex(false)
            let storage = CredentialStorage(read: base.read, write: { value, key in
                if !reject.withLock({ $0 }) { base.write(value, key) }
            })
            let identity = identity(storage)
            try await identity.saveSMSLogin(login(), expectedSessionID: identity.loginSessionID, authorizationOnly: false)
            let confirmed = Mutex(false)
            await identity.renewLoginIfNeeded(transport: { request in
                switch request.url!.lastPathComponent {
                case "info": return try self.response(request, ["code":0,"data":["mid":42,"expires_in":20,"refresh":true]])
                case "timestamp": return try self.response(request, ["code":0,"data":["timestamp":123]])
                case "refresh_token":
                    reject.withLock { $0 = failStorage }
                    return try self.response(request, self.refreshed(self.login("new", mid: failStorage ? "42" : "99")))
                default: confirmed.withLock { $0 = true }; return try self.response(request, ["code":0])
                }
            }, now: 100, device: device)
            let account = await identity.appAccount()
            XCTAssertEqual(account.accessKey, login().accessKey)
            XCTAssertFalse(confirmed.withLock { $0 })
        }
    }

    func testConcurrentActivationsShareOneValidation() async throws {
        let identity = identity(), gate = RenewalGate(), calls = Mutex(0)
        try await identity.saveSMSLogin(login(), expectedSessionID: identity.loginSessionID, authorizationOnly: false)
        let transport: AppLoginRenewal.Transport = { request in
            calls.withLock { $0 += 1 }
            await gate.pause()
            return try self.response(request, ["code":0,"data":["mid":42,"expires_in":3600,"refresh":false]])
        }
        let first = Task { await identity.renewLoginIfNeeded(transport: transport, now: 100, device: device) }
        await gate.waitUntilPaused()
        let second = Task { await identity.renewLoginIfNeeded(transport: transport, now: 100, device: device) }
        await gate.resume()
        await first.value; await second.value
        XCTAssertEqual(calls.withLock { $0 }, 1)
    }

    func testNativePassportEncodingMatchesIndependentGolden() {
        let values = AppSigner.signed(["test": "a!'()*~ +中文"], purpose: .passport, timestamp: 123, nativeEncoding: true)
        XCTAssertEqual(values["sign"], "7ce6d6e66aceaf55027979d699f1b46c")
        let encoded = AppSigner.queryString(from: values, nativeEncoding: true)
        XCTAssertTrue(encoded.contains("a%21%27%28%29%2A~%20%2B"))
    }

    func testExpiredTokenRequiresLoginWithoutDeletingCookiesOrRepeatingRequests() async throws {
        let identity = identity(), old = login(), calls = Mutex(0)
        try await identity.saveSMSLogin(old, expectedSessionID: identity.loginSessionID, authorizationOnly: false)
        let transport: AppLoginRenewal.Transport = { request in
            calls.withLock { $0 += 1 }
            return try self.response(request, ["code":61000])
        }
        await identity.renewLoginIfNeeded(transport: transport, now: 100, device: device)
        await identity.renewLoginIfNeeded(transport: transport, now: 10000, device: device)
        let cookies = await identity.loginCookies(), state = await identity.renewalState
        XCTAssertEqual(cookies, old.cookies)
        XCTAssertEqual(state, "needs-login")
        XCTAssertEqual(calls.withLock { $0 }, 1)
    }

    func testLocalDeviceIDHasIndependentGoldenChecksum() {
        let value = AppLocalDeviceID.generate(vendor: "00112233-4455-6677-8899-AABBCCDDEEFF", platform: "iPhone 17 Pro",
            firstRun: 1_700_000_000_000, date: Date(timeIntervalSince1970: 1_700_000_000), timeZone: TimeZone(secondsFromGMT: 0)!)
        XCTAssertEqual(value.count, 64)
        XCTAssertEqual(String(value.dropFirst(32).prefix(14)), "20231114221320")
        // Independent fixture generated with Python hashlib, not production Swift helpers.
        XCTAssertEqual(value, "CE871037C3D935603709744B813B7143202311142213201F137710E38A8E6714")
    }
}

private actor RenewalGate {
    private var blocked: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func pause() async {
        await withCheckedContinuation { blocked = $0; started?.resume(); started = nil }
    }
    func waitUntilPaused() async {
        if blocked != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func resume() { blocked?.resume(); blocked = nil }
}
