import Foundation

extension BiliAPI {
    // MARK: - 账号（登录后）

    /// 当前登录用户的个人信息。nav 对访客返回 code 0 但 `isLogin == false`，
    /// Cookie 失效时返回 -101，由 `AccountStore` 据此清理本地凭据。
    static func myProfile() async throws -> AccountProfilePayload {
        try await APIClient.shared.get(path: "x/web-interface/nav")
    }
}
