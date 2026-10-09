import Foundation
import Observation

@MainActor
@Observable
final class SMSLoginModel {
    struct Client {
        var prepare: () async throws -> SMSLoginModels.Context = { try await ApplicationServices.live.authentication.prepare() }
        var countries: () async throws -> [SMSLoginModels.Country] = { try await ApplicationServices.live.authentication.countries() }
        var send: (SMSLoginModels.Context, String, Int, SMSLoginModels.Captcha?, SMSLoginModels.ChallengeResult?) async throws -> SMSLoginModels.SendOutcome = {
            try await ApplicationServices.live.authentication.send(context: $0, phone: $1, country: $2, captcha: $3, result: $4)
        }
        var login: (SMSLoginModels.Context, String, Int, String, String) async throws -> SMSLoginModels.LoginOutcome = {
            try await ApplicationServices.live.authentication.login(context: $0, phone: $1, country: $2, code: $3, key: $4)
        }
        var exchange: (SMSLoginModels.Context, String) async throws -> SMSLoginModels.LoginOutcome = { try await ApplicationServices.live.authentication.exchange(context: $0, code: $1) }
    }
    struct Verification: Identifiable {
        let id = UUID()
        let url: URL
        let context: SMSLoginModels.Context
    }
    var phone = ""
    var code = ""
    var country = 1
    private(set) var countries: [SMSLoginModels.Country] = [.init(id: 1, cname: "中国大陆", countryId: "86")]
    private(set) var busy = false
    private(set) var error: String?
    private(set) var sent = false
    private(set) var resendAt = Date.distantPast
    var captcha: SMSLoginModels.Captcha?
    var verification: Verification?
    private(set) var credentials: SMSLoginModels.Credentials?
    private(set) var preparedAccountSession: UUID?
    private var context: SMSLoginModels.Context?
    private var captchaKey: String?
    private var pendingCaptchaID: String?
    private var expiresAt = Date.distantPast
    private var generation = UUID()
    private let client: Client
    init(client: Client = .init()) { self.client = client }

    // 地区列表 id 是选择器编号；App 的 cid 使用 country_id 电话区号。
    private var dialingCode: Int? {
        countries.first(where: { $0.id == country }).flatMap { Int($0.countryId) }.flatMap { $0 > 0 ? $0 : nil }
    }
    var validPhone: Bool {
        dialingCode != nil && !phone.isEmpty && phone.count >= 5 && phone.count <= 15 && phone.allSatisfy { $0.isASCII && $0.isNumber }
    }
    var validCode: Bool { code.count >= 4 && code.count <= 8 && code.allSatisfy { $0.isASCII && $0.isNumber } }
    var canLogin: Bool { !busy && sent && captchaKey != nil && validCode && Date() < expiresAt }
    func loadCountries() async {
        let current = generation
        do {
            let result = try await client.countries()
            guard generation == current, !Task.isCancelled else { return }
            if !result.isEmpty { countries = result }
        } catch { /* 列表不可用时保留中国大陆，App cid 使用电话区号 86。 */ }
    }
    func resetPhone() {
        generation = UUID()
        context = nil; captchaKey = nil; pendingCaptchaID = nil; sent = false; credentials = nil
        preparedAccountSession = nil; captcha = nil; verification = nil; code = ""; error = nil; busy = false
        // 倒计时不因修改号码或地区而绕过。
    }
    func cancel() { resetPhone() }
    func sendCode(result: SMSLoginModels.ChallengeResult? = nil, challenge: SMSLoginModels.Captcha? = nil) async {
        guard validPhone, let dialingCode, !busy, Date() >= resendAt || challenge != nil else { return }
        if let challenge {
            guard challenge.id == pendingCaptchaID, result != nil else { return }
            pendingCaptchaID = nil
        }
        let current = generation
        let phone = phone, country = dialingCode
        busy = true; error = nil; sent = false; captchaKey = nil
        defer { if generation == current { busy = false } }
        do {
            let prepared: SMSLoginModels.Context
            if let context { prepared = context } else { prepared = try await client.prepare() }
            guard generation == current, !Task.isCancelled else { return }
            context = prepared; preparedAccountSession = prepared.accountSession
            // 包括超时在内都先限制重发，避免用户误触产生多条短信。
            resendAt = Date().addingTimeInterval(60)
            let outcome = try await client.send(prepared, phone, country, challenge, result)
            guard generation == current, !Task.isCancelled else { return }
            switch outcome {
            case .sent(let key): captchaKey = key; sent = true; expiresAt = Date().addingTimeInterval(300)
            case .captcha(let request): pendingCaptchaID = request.id; captcha = request
            }
        } catch {
            guard generation == current, !Task.isCancelled else { return }
            self.error = LoginModels.failureText(for: error)
        }
    }
    func submit() async {
        guard !busy, sent, let context, let key = captchaKey, let dialingCode, validCode else { return }
        guard Date() < expiresAt else { error = String(localized: "验证码已过期，请重新获取"); return }
        let current = generation
        busy = true; error = nil
        defer { if generation == current { busy = false } }
        do {
            let outcome = try await client.login(context, phone, dialingCode, code, key)
            guard generation == current, !Task.isCancelled else { return }
            accept(outcome)
        } catch {
            guard generation == current, !Task.isCancelled else { return }
            self.error = LoginModels.failureText(for: error)
        }
    }
    func completeVerification(_ authorizationCode: String) async {
        guard !busy, verification != nil, let context, !authorizationCode.isEmpty else { return }
        let current = generation
        verification = nil; busy = true; error = nil
        defer { if generation == current { busy = false } }
        do {
            let outcome = try await client.exchange(context, authorizationCode)
            guard generation == current, !Task.isCancelled else { return }
            accept(outcome)
        } catch {
            guard generation == current, !Task.isCancelled else { return }
            self.error = LoginModels.failureText(for: error)
        }
    }
    private func accept(_ outcome: SMSLoginModels.LoginOutcome) {
        switch outcome {
        case .confirmed(let value): credentials = value; code = ""; captchaKey = nil
        case .verification(let url):
            if let context { verification = Verification(url: url, context: context) }
        }
    }
}
