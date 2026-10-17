#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation

extension AccountSessionClient {
    public static func live(identity: DeviceIdentity, client: APIClient) -> AccountSessionClient { AccountSessionClient(
        credentials: {
            // Startup/foreground services renew independently of cached account restoration.
            return await identity.accountSnapshot()
        },
        save: { await identity.saveLogin($0, accessKey: $1) },
        clear: { await identity.clearLoginCookies() },
        profile: { try await BiliAPI.myProfile(client: client) },
        exchangeAppCredential: {
            throw LoginModels.PassportError.rejected(String(localized: "请使用短信验证码重新授权"))
        },
        saveAppAuthorization: { key, mid in
            let session = identity.loginSessionID
            guard await identity.setAccessKey(key, forAccount: String(mid), expectedSessionID: session) else {
                throw CancellationError()
            }
        },
        saveSMS: { try await identity.saveSMSLogin($0, expectedSessionID: $1, authorizationOnly: $2) }
    ) }
}
