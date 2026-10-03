import XCTest
@testable import NeoBili

@MainActor
final class SMSLoginTests: XCTestCase {
    private func context() -> SMSPassport.Context {
        .init(accountSession: UUID(), headers: ["session_id": "own-session", "buvid": "own-buvid"],
              buvid: "own-buvid", deviceID: "server-device", loginSession: "login-attempt")
    }
    private func form(_ request: URLRequest) -> [String: String] {
        let raw = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        return Dictionary(raw.split(separator: "&").map {
            let parts = $0.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return (String(parts[0]).removingPercentEncoding!, String(parts[1]).removingPercentEncoding!)
        }, uniquingKeysWith: { _, new in new })
    }
    private func success(mid: Any = 42, cookieMid: String = "42") -> [String: Any] {
        ["code": 0, "data": ["status": 0, "token_info": ["mid": mid, "access_token": "fixture-token"],
                              "cookie_info": ["cookies": [["name": "SESSDATA", "value": "s%2Cvalue"], ["name": "bili_jct", "value": "csrf"], ["name": "DedeUserID", "value": cookieMid]]]]]
    }
    func testLoginAndExchangeUseSameOwnIdentityAndSignedForm() {
        let identity = context()
        for path in ["x/passport-login/sms/send", "x/passport-login/login/sms", "x/passport-login/oauth2/access_token"] {
            let request = SMSPassport.makeRequest(path: path, context: identity, fields: ["login_session_id": identity.loginSession, "code": "001234"])
            let fields = form(request)
            XCTAssertEqual(request.url?.host, "passport.bilibili.com")
            XCTAssertEqual(fields["buvid"], "own-buvid")
            XCTAssertEqual(fields["local_id"], "own-buvid")
            XCTAssertEqual(fields["device_id"], "server-device")
            XCTAssertEqual(fields["mobi_app"], "iphone")
            XCTAssertEqual(fields["device_name"], "iPhone")
            XCTAssertEqual(fields["code"], "001234")
            XCTAssertEqual(request.value(forHTTPHeaderField: "buvid"), "own-buvid")
            XCTAssertEqual(request.value(forHTTPHeaderField: "session_id"), "own-session")
            XCTAssertFalse(request.httpShouldHandleCookies)
            XCTAssertNil(fields["device_meta"], "Unknown encrypted data must not be invented")
            var unsigned = fields; unsigned.removeValue(forKey: "sign")
            XCTAssertEqual(fields["sign"], AppSigner.signed(unsigned, purpose: .passport)["sign"])
        }
    }
    func testSecurityVerificationCarriesSameAppIdentityAndPreservesAnswers() throws {
        let url = URL(string: "https://api.bilibili.com/x/safecenter/answer/submit?web_location=333.999")!
        let request = try SMSPassport.securityRequest(url: url, method: "POST", body: "hid=fixture&tmp_code=temporary&answer1=A%2BB&appkey=wrong&buvid=wrong", context: context())
        var body = URLRequest(url: url); body.httpBody = request["body"]!.data(using: .utf8)
        let values = form(body)
        XCTAssertEqual(values["appkey"], AppSigner.passportAppKey)
        XCTAssertEqual(values["mobi_app"], AppClientIdentity.mobiApp)
        XCTAssertEqual(values["buvid"], "own-buvid")
        XCTAssertEqual(values["answer1"], "A+B")
        XCTAssertEqual(values["tmp_code"], "temporary")
        var unsigned = values; unsigned.removeValue(forKey: "sign")
        XCTAssertEqual(values["sign"], AppSigner.signed(unsigned, purpose: .passport)["sign"])
        let query = URLComponents(string: request["url"]!)!.queryItems!
        XCTAssertEqual(query.first(where: { $0.name == "appkey" })?.value, AppSigner.passportAppKey)
        XCTAssertEqual(query.first(where: { $0.name == "web_location" })?.value, "333.999")
        XCTAssertFalse(query.contains(where: { $0.name == "answer1" }))
    }
    func testSecuritySignerRejectsForeignHostUnrelatedPathsAndDuplicateFields() throws {
        for raw in ["http://api.bilibili.com/x/safecenter/answer/submit", "https://api.bilibili.com.attacker.invalid/x/safecenter/answer/submit", "https://api.bilibili.com/x/web-interface/archive/like"] {
            XCTAssertThrowsError(try SMSPassport.securityRequest(url: URL(string: raw)!, method: "POST", body: "hid=fixture", context: context()))
        }
        let url = URL(string: "https://api.bilibili.com/x/safecenter/answer/questions?tmp_code=fixture")!
        XCTAssertThrowsError(try SMSPassport.securityRequest(url: url, method: "POST", body: "hid=one&hid=two", context: context()))
        let get = try SMSPassport.securityRequest(url: url, method: "GET", body: "", context: context())
        XCTAssertEqual(get["body"], "")
        XCTAssertTrue(get["url"]!.contains("sign="))
    }
    func testSMSResponseDoesNotTreatRateLimitOrMissingKeyAsSent() throws {
        guard case .sent(let key) = try SMSPassport.sendOutcome(["code": 0, "data": ["captcha_key": "fixture"]]) else { return XCTFail() }
        XCTAssertEqual(key, "fixture")
        XCTAssertThrowsError(try SMSPassport.sendOutcome(["code": 86005, "message": "发送频繁", "data": ["captcha_key": "", "recaptcha_url": ""]]))
        XCTAssertThrowsError(try SMSPassport.sendOutcome(["code": 0, "data": [:]]))
    }
    func testRecaptchaIsTakenFromServerChallengeAndResubmitted() throws {
        let params = #"{"recaptcha_token":"server-token","gt":"server-gt","challenge":"server-challenge"}"#.data(using: .utf8)!.base64EncodedString()
        var url = URLComponents(string: "https://passport.bilibili.com/captcha")!
        url.queryItems = [.init(name: "params", value: params)]
        guard case .captcha(let captcha) = try SMSPassport.sendOutcome(["code": 86004, "data": ["recaptcha_url": url.string!]]) else { return XCTFail() }
        XCTAssertEqual(captcha.token, "server-token")
        XCTAssertEqual(captcha.gt, "server-gt")
        XCTAssertEqual(captcha.challenge, "server-challenge")
    }
    func testUnknownCaptchaCannotClaimSMSWasSent() {
        XCTAssertThrowsError(try SMSPassport.sendOutcome(["code": 86004, "data": ["recaptcha_url": "https://passport.bilibili.com/captcha?unknown=1"]]))
    }
    func testNestedAppCredentialsRequireMatchingTokenAndCookieAccount() throws {
        guard case .confirmed(let result) = try SMSPassport.loginOutcome(success()) else { return XCTFail() }
        XCTAssertEqual(result.accessKey, "fixture-token")
        XCTAssertEqual(result.cookies.sessdata, "s%2Cvalue")
        guard case .confirmed = try SMSPassport.loginOutcome(success(mid: "42")) else { return XCTFail() }
        XCTAssertThrowsError(try SMSPassport.loginOutcome(success(cookieMid: "43")))
        XCTAssertThrowsError(try SMSPassport.loginOutcome(["code": 0, "data": ["status": 0]]))
        XCTAssertThrowsError(try SMSPassport.loginOutcome(["code": 1006, "message": "验证码错误", "data": [:]]))
    }
    func testAdditionalSecurityValidationIsNotSuccessfulLogin() throws {
        let value: [String: Any] = ["code": 0, "data": ["status": 5, "url": "https://passport.bilibili.com/h5/project-msg-auth/auth/entry?tmp_token=fixture"]]
        guard case .verification(let url) = try SMSPassport.loginOutcome(value) else { return XCTFail() }
        XCTAssertTrue(SMSPassport.isSecurityURL(url))
        XCTAssertThrowsError(try SMSPassport.loginOutcome(["code": 0, "data": ["status": 5, "url": "https://passport.bilibili.com.attacker.invalid/h5/project-msg-auth/auth/entry"]]))
        XCTAssertFalse(SMSPassport.isSecurityURL(URL(string: "http://passport.bilibili.com/h5/project-msg-auth/auth/entry")!))
    }
    func testSMSWriteDoesNotAutomaticallyRetryAfterTimeout() async {
        actor Counter { var count = 0; func increment() { count += 1 } }
        let counter = Counter()
        do {
            _ = try await SMSPassport.send(context: context(), phone: "13000000000", country: 86, transport: { _ in
                await counter.increment(); throw URLError(.timedOut)
            })
            XCTFail()
        } catch {}
        let count = await counter.count
        XCTAssertEqual(count, 1)
    }
    func testModelUsesSameAttemptForSendingAndSubmittingAndPreservesLeadingZeroCode() async {
        let fixture = context()
        var sends = 0, logins = 0
        let model = SMSLoginModel(client: .init(prepare: { fixture }, countries: { [] }, send: { ctx, phone, cid, _, _ in
            sends += 1; XCTAssertEqual(ctx.loginSession, fixture.loginSession); XCTAssertEqual(phone, "13000000000"); XCTAssertEqual(cid, 86)
            return .sent("captcha-key")
        }, login: { ctx, _, cid, code, key in
            XCTAssertEqual(cid, 86)
            logins += 1; XCTAssertEqual(ctx.loginSession, fixture.loginSession); XCTAssertEqual(code, "001234"); XCTAssertEqual(key, "captcha-key")
            return .confirmed(.init(cookies: .init(sessdata: "s", biliJct: "j", dedeUserID: "42"), accessKey: "token"))
        }))
        model.phone = "13000000000"
        await model.sendCode(); await model.sendCode()
        XCTAssertEqual(sends, 1, "Countdown prevents duplicate sends")
        model.code = "001234"; await model.submit()
        XCTAssertEqual(logins, 1); XCTAssertEqual(model.credentials?.accessKey, "token")
    }
    func testCountrySelectionUsesDialingCodeRatherThanListIdentifier() async {
        let fixture = context()
        var sentCode: Int?
        let model = SMSLoginModel(client: .init(prepare: { fixture }, countries: {
            [.init(id: 1, cname: "中国大陆", countryId: "86"), .init(id: 7, cname: "测试地区", countryId: "44")]
        }, send: { _, _, cid, _, _ in sentCode = cid; return .sent("key") }))
        await model.loadCountries()
        model.country = 7; model.phone = "7000000000"
        await model.sendCode()
        XCTAssertEqual(sentCode, 44)
    }
    func testChangingPhoneInvalidatesSMSKeyAndDoesNotBypassCooldown() async {
        let fixture = context()
        let model = SMSLoginModel(client: .init(prepare: { fixture }, send: { _, _, _, _, _ in .sent("key") }))
        model.phone = "13000000000"; await model.sendCode(); model.code = "123456"
        XCTAssertTrue(model.canLogin)
        let limit = model.resendAt
        model.phone = "13000000001"; model.resetPhone()
        XCTAssertFalse(model.sent); XCTAssertFalse(model.canLogin); XCTAssertEqual(model.resendAt, limit)
    }
    func testCancelledAttemptCannotPublishLateCredentials() async {
        let fixture = context()
        var resume: CheckedContinuation<SMSPassport.LoginOutcome, Never>?
        let model = SMSLoginModel(client: .init(prepare: { fixture }, send: { _, _, _, _, _ in .sent("key") }, login: { _, _, _, _, _ in
            await withCheckedContinuation { resume = $0 }
        }))
        model.phone = "13000000000"; await model.sendCode(); model.code = "123456"
        let pending = Task { await model.submit() }
        while resume == nil { await Task.yield() }
        model.cancel()
        resume?.resume(returning: .confirmed(.init(cookies: .init(sessdata: "s", biliJct: "j", dedeUserID: "42"), accessKey: "token")))
        await pending.value
        XCTAssertNil(model.credentials); XCTAssertFalse(model.busy)
    }
    func testAdditionalValidationExchangesCodeWithinSameAttempt() async {
        let fixture = context()
        let model = SMSLoginModel(client: .init(prepare: { fixture }, send: { _, _, _, _, _ in .sent("key") }, login: { _, _, _, _, _ in
            .verification(URL(string: "https://passport.bilibili.com/h5/project-msg-auth/auth/entry?tmp_token=fixture")!)
        }, exchange: { ctx, code in
            XCTAssertEqual(ctx.loginSession, fixture.loginSession); XCTAssertEqual(code, "server-authorization-code")
            return .confirmed(.init(cookies: .init(sessdata: "s", biliJct: "j", dedeUserID: "42"), accessKey: "token"))
        }))
        model.phone = "13000000000"; await model.sendCode(); model.code = "123456"; await model.submit()
        XCTAssertNotNil(model.verification); XCTAssertNil(model.credentials)
        await model.completeVerification("server-authorization-code")
        XCTAssertNil(model.verification); XCTAssertEqual(model.credentials?.accessKey, "token")
    }
    func testSMSAccountAuthorizationRejectsOtherAccountWithoutChangingLogin() async throws {
        var writes = 0
        let account = AccountStore(client: .init(credentials: { .init(hasCredentials: true, accountID: 42) }, save: { _, _ in XCTFail() }, clear: {}, profile: { throw URLError(.notConnectedToInternet) }, saveAppAuthorization: { _, _ in writes += 1 }), monitorNetwork: false)
        await account.restoreSessionIfNeeded()
        do {
            try await account.completeAppAuthorization(.init(sessdata: "s", biliJct: "j", dedeUserID: "43"), accessKey: "fixture", expectedSessionID: account.sessionID)
            XCTFail()
        } catch {}
        XCTAssertEqual(writes, 0); XCTAssertEqual(account.accountID, 42); XCTAssertTrue(account.isLoggedIn)
    }
}
