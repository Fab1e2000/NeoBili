import Foundation

struct AccountCredentialsSnapshot: Sendable {
    let hasCredentials: Bool
    var hasAppCredential = false
    var needsAppReauthorization = false
    var needsAppCredentialMigration = false
    let accountID: Int?
}

/// 可以注入内存凭据与假接口，回归测试不接触用户的 Keychain。
@MainActor
struct AccountSessionClient {
    var credentials: @MainActor () async -> AccountCredentialsSnapshot
    var save: @MainActor (LoginModels.LoginCookies, String?) async -> Void
    var clear: @MainActor () async -> Void
    var profile: @MainActor () async throws -> AccountProfilePayload
    /// 用当前 Cookie 换一份 App 凭据并保存。
    var exchangeAppCredential: @MainActor () async throws -> Void = {}

    var saveAppAuthorization: @MainActor (String, Int) async throws -> Void = { _, _ in throw BiliAPIError.missingAccessKey }

    var saveSMS: (@MainActor (SMSLoginModels.Credentials, UUID, Bool) async throws -> Void)? = nil


}
