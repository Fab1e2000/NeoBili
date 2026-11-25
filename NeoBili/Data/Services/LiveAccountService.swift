import NeoBiliDomain
import Foundation

extension AccountService {
    public static func live(client: APIClient) -> Self {
        Self(
            myProfileOperation: {
                try await BiliAPI.myProfile(client: client)
            }
        )
    }
}
