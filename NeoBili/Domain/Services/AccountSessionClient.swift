import Foundation

public struct AccountCredentialsSnapshot: Sendable {
    public let hasCredentials: Bool
    public var hasAppCredential = false
    public var needsAppReauthorization = false
    public var needsAppCredentialMigration = false
    public let accountID: Int?

    public init(
        hasCredentials: Bool,
        hasAppCredential: Bool = false,
        needsAppReauthorization: Bool = false,
        needsAppCredentialMigration: Bool = false,
        accountID: Int? = nil
    ) {
        self.hasCredentials = hasCredentials
        self.hasAppCredential = hasAppCredential
        self.needsAppReauthorization = needsAppReauthorization
        self.needsAppCredentialMigration = needsAppCredentialMigration
        self.accountID = accountID
    }
}

/// 可以注入内存凭据与假接口，回归测试不接触用户的 Keychain。
@MainActor
public struct AccountSessionClient {
    public var credentials: @MainActor () async -> AccountCredentialsSnapshot
    public var save: @MainActor (LoginModels.LoginCookies, String?) async -> Void
    public var clear: @MainActor () async -> Void
    public var profile: @MainActor () async throws -> AccountProfilePayload
    /// 用当前 Cookie 换一份 App 凭据并保存。
    public var exchangeAppCredential: @MainActor () async throws -> Void = {}

    public var saveAppAuthorization: @MainActor (String, Int) async throws -> Void = { _, _ in throw BiliAPIError.missingAccessKey }

    public var saveSMS: (@MainActor (SMSLoginModels.Credentials, UUID, Bool) async throws -> Void)? = nil

    public init(
        credentials: @escaping @MainActor () async -> AccountCredentialsSnapshot,
        save: @escaping @MainActor (LoginModels.LoginCookies, String?) async -> Void,
        clear: @escaping @MainActor () async -> Void,
        profile: @escaping @MainActor () async throws -> AccountProfilePayload,
        exchangeAppCredential: @escaping @MainActor () async throws -> Void = {},
        saveAppAuthorization: @escaping @MainActor (String, Int) async throws -> Void = { _, _ in throw BiliAPIError.missingAccessKey },
        saveSMS: (@MainActor (SMSLoginModels.Credentials, UUID, Bool) async throws -> Void)? = nil
    ) {
        self.credentials = credentials
        self.save = save
        self.clear = clear
        self.profile = profile
        self.exchangeAppCredential = exchangeAppCredential
        self.saveAppAuthorization = saveAppAuthorization
        self.saveSMS = saveSMS
    }

}
