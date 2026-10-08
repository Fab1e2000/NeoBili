import Foundation

extension AccountService {
    static func live(client: APIClient = .shared) -> Self {
        Self(
            myProfileOperation: {
                try await BiliAPI.myProfile()
            }
        )
    }
}
