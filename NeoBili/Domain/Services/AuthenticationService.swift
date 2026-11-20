import Foundation

public struct AuthenticationService: Sendable {
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
        prepareOperation: @escaping @Sendable () async throws -> SMSLoginModels.Context = { throw ServiceError.unconfigured("Authentication.prepare") },
        countriesOperation: @escaping @Sendable () async throws -> [SMSLoginModels.Country] = { throw ServiceError.unconfigured("Authentication.countries") },
        sendOperation: @escaping @Sendable (SMSLoginModels.Context, String, Int, SMSLoginModels.Captcha?, SMSLoginModels.ChallengeResult?) async throws -> SMSLoginModels.SendOutcome = { _, _, _, _, _ in throw ServiceError.unconfigured("Authentication.send") },
        loginOperation: @escaping @Sendable (SMSLoginModels.Context, String, Int, String, String) async throws -> SMSLoginModels.LoginOutcome = { _, _, _, _, _ in throw ServiceError.unconfigured("Authentication.login") },
        exchangeOperation: @escaping @Sendable (SMSLoginModels.Context, String) async throws -> SMSLoginModels.LoginOutcome = { _, _ in throw ServiceError.unconfigured("Authentication.exchange") },
        securityRequestOperation: @escaping @Sendable (URL, String, String, SMSLoginModels.Context) throws -> [String: String] = { _, _, _, _ in throw ServiceError.unconfigured("Authentication.securityRequest") }
    ) {
        self.prepareOperation = prepareOperation
        self.countriesOperation = countriesOperation
        self.sendOperation = sendOperation
        self.loginOperation = loginOperation
        self.exchangeOperation = exchangeOperation
        self.securityRequestOperation = securityRequestOperation
    }
}
