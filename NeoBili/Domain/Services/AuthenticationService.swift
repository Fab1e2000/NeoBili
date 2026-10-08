import Foundation

struct AuthenticationService: Sendable {
    var encryptPassword: @Sendable (String, String, String) throws -> String = { _, _, _ in throw ServiceError.unconfigured("encryptPassword") }
    var generateQRCodeOperation: @Sendable () async throws -> LoginModels.QRCodeInfo = { throw ServiceError.unconfigured("Authentication.generateQRCode") }

    func generateQRCode() async throws -> LoginModels.QRCodeInfo {
        try await generateQRCodeOperation()
    }

    var pollQRCodeOperation: @Sendable (String) async throws -> LoginModels.QRCodePollOutcome = { _ in throw ServiceError.unconfigured("Authentication.pollQRCode") }

    func pollQRCode(_ qrcodeKey: String) async throws -> LoginModels.QRCodePollOutcome {
        try await pollQRCodeOperation(qrcodeKey)
    }

    var generateAppQRCodeOperation: @Sendable () async throws -> LoginModels.AppQRCodeInfo = { throw ServiceError.unconfigured("Authentication.generateAppQRCode") }

    func generateAppQRCode() async throws -> LoginModels.AppQRCodeInfo {
        try await generateAppQRCodeOperation()
    }

    var pollAppQRCodeOperation: @Sendable (String, LoginModels.LoginCookies?) async throws -> LoginModels.QRCodePollOutcome = { _, _ in throw ServiceError.unconfigured("Authentication.pollAppQRCode") }

    func pollAppQRCode(_ authCode: String, fallbackCookies: LoginModels.LoginCookies? = nil) async throws -> LoginModels.QRCodePollOutcome {
        try await pollAppQRCodeOperation(authCode, fallbackCookies)
    }

    var webKeyOperation: @Sendable () async throws -> LoginModels.WebKey = { throw ServiceError.unconfigured("Authentication.webKey") }

    func webKey() async throws -> LoginModels.WebKey {
        try await webKeyOperation()
    }

    var captchaOperation: @Sendable () async throws -> LoginModels.CaptchaInfo = { throw ServiceError.unconfigured("Authentication.captcha") }

    func captcha() async throws -> LoginModels.CaptchaInfo {
        try await captchaOperation()
    }

    var passwordLoginOperation: @Sendable (String, String, String, String, String, String) async throws -> LoginModels.LoginCookies = { _, _, _, _, _, _ in throw ServiceError.unconfigured("Authentication.passwordLogin") }

    func passwordLogin(username: String, passwordEncrypted: String, captchaToken: String, challenge: String, validate: String, seccode: String) async throws -> LoginModels.LoginCookies {
        try await passwordLoginOperation(username, passwordEncrypted, captchaToken, challenge, validate, seccode)
    }

    var prepareOperation: @Sendable () async throws -> SMSLoginModels.Context = { throw ServiceError.unconfigured("Authentication.prepare") }

    func prepare() async throws -> SMSLoginModels.Context {
        try await prepareOperation()
    }

    var countriesOperation: @Sendable () async throws -> [SMSLoginModels.Country] = { throw ServiceError.unconfigured("Authentication.countries") }

    func countries() async throws -> [SMSLoginModels.Country] {
        try await countriesOperation()
    }

    var sendOperation: @Sendable (SMSLoginModels.Context, String, Int, SMSLoginModels.Captcha?, SMSLoginModels.ChallengeResult?) async throws -> SMSLoginModels.SendOutcome = { _, _, _, _, _ in throw ServiceError.unconfigured("Authentication.send") }

    func send(context: SMSLoginModels.Context, phone: String, country: Int, captcha: SMSLoginModels.Captcha? = nil, result: SMSLoginModels.ChallengeResult? = nil) async throws -> SMSLoginModels.SendOutcome {
        try await sendOperation(context, phone, country, captcha, result)
    }

    var loginOperation: @Sendable (SMSLoginModels.Context, String, Int, String, String) async throws -> SMSLoginModels.LoginOutcome = { _, _, _, _, _ in throw ServiceError.unconfigured("Authentication.login") }

    func login(context: SMSLoginModels.Context, phone: String, country: Int, code: String, key: String) async throws -> SMSLoginModels.LoginOutcome {
        try await loginOperation(context, phone, country, code, key)
    }

    var exchangeOperation: @Sendable (SMSLoginModels.Context, String) async throws -> SMSLoginModels.LoginOutcome = { _, _ in throw ServiceError.unconfigured("Authentication.exchange") }

    func exchange(context: SMSLoginModels.Context, code: String) async throws -> SMSLoginModels.LoginOutcome {
        try await exchangeOperation(context, code)
    }

    var securityRequestOperation: @Sendable (URL, String, String, SMSLoginModels.Context) throws -> [String: String] = { _, _, _, _ in throw ServiceError.unconfigured("Authentication.securityRequest") }

    func securityRequest(url: URL, method: String, body: String, context: SMSLoginModels.Context) throws -> [String: String] {
        try securityRequestOperation(url, method, body, context)
    }

}
