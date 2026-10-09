import Foundation

extension SessionService {
    static func live(identity: DeviceIdentity = .shared) -> Self {
        Self(currentID: { identity.loginSessionID }, homeAccount: {
            let account = await identity.appAccount()
            return HomeFeedAccount(accountID: account.mid, hasAppCredential: account.accessKey != nil)
        })
    }
}
