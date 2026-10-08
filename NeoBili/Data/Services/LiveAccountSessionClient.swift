import Foundation

extension AccountSessionClient {
    static var live: AccountSessionClient { AccountSessionClient(
        credentials: {
            // Startup/foreground services renew independently of cached account restoration.
            return await DeviceIdentity.shared.accountSnapshot()
        },
        save: { await DeviceIdentity.shared.saveLogin($0, accessKey: $1) },
        clear: { await DeviceIdentity.shared.clearLoginCookies() },
        profile: { try await BiliAPI.myProfile() },
        exchangeAppCredential: {
            throw LoginModels.PassportError.rejected(String(localized: "请使用短信验证码重新授权"))
        },
        saveAppAuthorization: { key, mid in
            let session = DeviceIdentity.shared.loginSessionID
            guard await DeviceIdentity.shared.setAccessKey(key, forAccount: String(mid), expectedSessionID: session) else {
                throw CancellationError()
            }
        },
        saveSMS: { try await DeviceIdentity.shared.saveSMSLogin($0, expectedSessionID: $1, authorizationOnly: $2) }
    ) }
}
