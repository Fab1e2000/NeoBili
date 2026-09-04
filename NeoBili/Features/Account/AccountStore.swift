import Foundation
import SwiftUI

/// 登录会话与账号信息。
///
/// Cookie 本体由 `DeviceIdentity` 保管（Keychain），这里只负责「登录流程」和
/// 「当前用户是谁」：扫码/密码登录成功后写入 Cookie 并拉取个人信息；冷启动
/// 时若 Keychain 里还有凭据就先恢复会话；登出时清空两者。
@MainActor
@Observable
final class AccountStore {
    struct Profile: Equatable, Sendable {
        let mid: Int
        let name: String
        let face: String?
        let level: Int
        let coins: Double
        let isVIP: Bool

        var secureAvatarURL: URL? {
            face.flatMap { URL.biliSecure($0) }
        }
    }

    private(set) var profile: Profile?
    /// 冷启动恢复会话期间为 true，此时「我的」页不显示登录入口，避免闪一下。
    private(set) var isRestoringSession = true

    var isLoggedIn: Bool { profile != nil }

    /// Cookie 失效（-101）时清除本地凭据并回到未登录态；普通网络失败不动作，
    /// 免得一次超时就把用户「登出」。
    func restoreSessionIfNeeded() async {
        defer { isRestoringSession = false }
        guard await DeviceIdentity.shared.isLoggedIn else { return }
        await refreshProfile()
    }

    func refreshProfile() async {
        do {
            let payload = try await BiliAPI.myProfile()
            if payload.isLogin == true, let mid = payload.mid, let name = payload.uname {
                profile = Profile(
                    mid: mid,
                    name: name,
                    face: payload.face,
                    level: payload.levelInfo?.currentLevel ?? 0,
                    coins: payload.money ?? 0,
                    isVIP: (payload.vipStatus ?? 0) == 1
                )
            } else {
                // 服务端明确说没登录：凭据已经无效，清掉。
                profile = nil
                await DeviceIdentity.shared.clearLoginCookies()
            }
        } catch BiliAPIError.apiError(let code, _) where code == -101 {
            profile = nil
            await DeviceIdentity.shared.clearLoginCookies()
        } catch {
            // 网络抖动：保留现有凭据，下次再试。
        }
    }

    /// 扫码或密码登录成功后的共同出口：写入凭据 → 拉个人信息。
    func completeLogin(_ cookies: BiliPassport.LoginCookies) async {
        await DeviceIdentity.shared.setLoginCookies(
            sessdata: cookies.sessdata,
            biliJct: cookies.biliJct,
            dedeUserID: cookies.dedeUserID
        )
        await refreshProfile()
    }

    func logout() async {
        await DeviceIdentity.shared.clearLoginCookies()
        profile = nil
    }
}
