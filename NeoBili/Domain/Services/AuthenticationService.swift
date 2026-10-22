import Foundation

public struct AuthenticationService: Sendable {
    public var encryptPassword: @Sendable (String, String, String) throws -> String = { _, _, _ in throw ServiceError.unconfigured("encryptPassword") }
    public var generateQRCodeOperation: @Sendable () async throws -> LoginModels.QRCodeInfo = { throw ServiceError.unconfigured("Authentication.generateQRCode") }

    public func generateQRCode() async throws -> LoginModels.QRCodeInfo {
        try await generateQRCodeOperation()
    }

    public var pollQRCodeOperation: @Sendable (String) async throws -> LoginModels.QRCodePollOutcome = { _ in throw ServiceError.unconfigured("Authentication.pollQRCode") }

    public func pollQRCode(_ qrcodeKey: String) async throws -> LoginModels.QRCodePollOutcome {
        try await pollQRCodeOperation(qrcodeKey)
    }

    public var generateAppQRCodeOperation: @Sendable () async throws -> LoginModels.AppQRCodeInfo = { throw ServiceError.unconfigured("Authentication.generateAppQRCode") }

    public func generateAppQRCode() async throws -> LoginModels.AppQRCodeInfo {
        try await generateAppQRCodeOperation()
    }

    public var pollAppQRCodeOperation: @Sendable (String, LoginModels.LoginCookies?) async throws -> LoginModels.QRCodePollOutcome = { _, _ in throw ServiceError.unconfigured("Authentication.pollAppQRCode") }

    public func pollAppQRCode(_ authCode: String, fallbackCookies: LoginModels.LoginCookies? = nil) async throws -> LoginModels.QRCodePollOutcome {
        try await pollAppQRCodeOperation(authCode, fallbackCookies)
    }

    public var webKeyOperation: @Sendable () async throws -> LoginModels.WebKey = { throw ServiceError.unconfigured("Authentication.webKey") }

    public func webKey() async throws -> LoginModels.WebKey {
        try await webKeyOperation()
    }

    public var captchaOperation: @Sendable () async throws -> LoginModels.CaptchaInfo = { throw ServiceError.unconfigured("Authentication.captcha") }

    public func captcha() async throws -> LoginModels.CaptchaInfo {
        try await captchaOperation()
    }

    public var passwordLoginOperation: @Sendable (String, String, String, String, String, String) async throws -> LoginModels.LoginCookies = { _, _, _, _, _, _ in throw ServiceError.unconfigured("Authentication.passwordLogin") }

    public func passwordLogin(username: String, passwordEncrypted: String, captchaToken: String, challenge: String, validate: String, seccode: String) async throws -> LoginModels.LoginCookies {
        try await passwordLoginOperation(username, passwordEncrypted, captchaToken, challenge, validate, seccode)
    }

    public var prepareOperation: @Sendable () async throws -> SMSLoginModels.Context = { throw ServiceError.unconfigured("Authentication.prepare") }

    public func prepare() async throws -> SMSLoginModels.Context {
        try await prepareOperation()
    }

    public var countriesOperation: @Sendable () async throws -> [SMSLoginModels.Country] = { throw ServiceError.unconfigured("Authentication.countries") }

    public func countries() async throws -> [SMSLoginModels.Country] {
        try await countriesOperation()
    }

    public var sendOperation: @Sendable (SMSLoginModels.Context, String, Int, SMSLoginModels.Captcha?, SMSLoginModels.ChallengeResult?) async throws -> SMSLoginModels.SendOutcome = { _, _, _, _, _ in throw ServiceError.unconfigured("Authentication.send") }

    public func send(context: SMSLoginModels.Context, phone: String, country: Int, captcha: SMSLoginModels.Captcha? = nil, result: SMSLoginModels.ChallengeResult? = nil) async throws -> SMSLoginModels.SendOutcome {
        try await sendOperation(context, phone, country, captcha, result)
    }

    public var loginOperation: @Sendable (SMSLoginModels.Context, String, Int, String, String) async throws -> SMSLoginModels.LoginOutcome = { _, _, _, _, _ in throw ServiceError.unconfigured("Authentication.login") }

    public func login(context: SMSLoginModels.Context, phone: String, country: Int, code: String, key: String) async throws -> SMSLoginModels.LoginOutcome {
        try await loginOperation(context, phone, country, code, key)
    }

    public var exchangeOperation: @Sendable (SMSLoginModels.Context, String) async throws -> SMSLoginModels.LoginOutcome = { _, _ in throw ServiceError.unconfigured("Authentication.exchange") }

    public func exchange(context: SMSLoginModels.Context, code: String) async throws -> SMSLoginModels.LoginOutcome {
        try await exchangeOperation(context, code)
    }

    public var securityRequestOperation: @Sendable (URL, String, String, SMSLoginModels.Context) throws -> [String: String] = { _, _, _, _ in throw ServiceError.unconfigured("Authentication.securityRequest") }

    public func securityRequest(url: URL, method: String, body: String, context: SMSLoginModels.Context) throws -> [String: String] {
        try securityRequestOperation(url, method, body, context)
    }

    public init(
        encryptPassword: @escaping @Sendable (String, String, String) throws -> String = { _, _, _ in throw ServiceError.unconfigured("encryptPassword") },
        generateQRCodeOperation: @escaping @Sendable () async throws -> LoginModels.QRCodeInfo = { throw ServiceError.unconfigured("Authentication.generateQRCode") },
        pollQRCodeOperation: @escaping @Sendable (String) async throws -> LoginModels.QRCodePollOutcome = { _ in throw ServiceError.unconfigured("Authentication.pollQRCode") },
        generateAppQRCodeOperation: @escaping @Sendable () async throws -> LoginModels.AppQRCodeInfo = { throw ServiceError.unconfigured("Authentication.generateAppQRCode") },
        pollAppQRCodeOperation: @escaping @Sendable (String, LoginModels.LoginCookies?) async throws -> LoginModels.QRCodePollOutcome = { _, _ in throw ServiceError.unconfigured("Authentication.pollAppQRCode") },
        webKeyOperation: @escaping @Sendable () async throws -> LoginModels.WebKey = { throw ServiceError.unconfigured("Authentication.webKey") },
        captchaOperation: @escaping @Sendable () async throws -> LoginModels.CaptchaInfo = { throw ServiceError.unconfigured("Authentication.captcha") },
        passwordLoginOperation: @escaping @Sendable (String, String, String, String, String, String) async throws -> LoginModels.LoginCookies = { _, _, _, _, _, _ in throw ServiceError.unconfigured("Authentication.passwordLogin") },
        prepareOperation: @escaping @Sendable () async throws -> SMSLoginModels.Context = { throw ServiceError.unconfigured("Authentication.prepare") },
        countriesOperation: @escaping @Sendable () async throws -> [SMSLoginModels.Country] = { throw ServiceError.unconfigured("Authentication.countries") },
        sendOperation: @escaping @Sendable (SMSLoginModels.Context, String, Int, SMSLoginModels.Captcha?, SMSLoginModels.ChallengeResult?) async throws -> SMSLoginModels.SendOutcome = { _, _, _, _, _ in throw ServiceError.unconfigured("Authentication.send") },
        loginOperation: @escaping @Sendable (SMSLoginModels.Context, String, Int, String, String) async throws -> SMSLoginModels.LoginOutcome = { _, _, _, _, _ in throw ServiceError.unconfigured("Authentication.login") },
        exchangeOperation: @escaping @Sendable (SMSLoginModels.Context, String) async throws -> SMSLoginModels.LoginOutcome = { _, _ in throw ServiceError.unconfigured("Authentication.exchange") },
        securityRequestOperation: @escaping @Sendable (URL, String, String, SMSLoginModels.Context) throws -> [String: String] = { _, _, _, _ in throw ServiceError.unconfigured("Authentication.securityRequest") }
    ) {
        self.encryptPassword = encryptPassword
        self.generateQRCodeOperation = generateQRCodeOperation
        self.pollQRCodeOperation = pollQRCodeOperation
        self.generateAppQRCodeOperation = generateAppQRCodeOperation
        self.pollAppQRCodeOperation = pollAppQRCodeOperation
        self.webKeyOperation = webKeyOperation
        self.captchaOperation = captchaOperation
        self.passwordLoginOperation = passwordLoginOperation
        self.prepareOperation = prepareOperation
        self.countriesOperation = countriesOperation
        self.sendOperation = sendOperation
        self.loginOperation = loginOperation
        self.exchangeOperation = exchangeOperation
        self.securityRequestOperation = securityRequestOperation
    }
}
