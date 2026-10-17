#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation

extension AccountService {
    static func live(client: APIClient) -> Self {
        Self(
            myProfileOperation: {
                try await BiliAPI.myProfile(client: client)
            }
        )
    }
}
