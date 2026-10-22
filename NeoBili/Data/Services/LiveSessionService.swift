#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation

extension SessionService {
    public static func live(identity: DeviceIdentity) -> Self {
        Self(currentID: { identity.loginSessionID }, homeAccount: {
            let account = await identity.appAccount()
            return HomeFeedAccount(accountID: account.mid, hasAppCredential: account.accessKey != nil)
        })
    }
}
