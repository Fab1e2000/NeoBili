import Foundation
import SwiftUI
import Network

struct AccountCredentialsSnapshot: Sendable {
    let hasCredentials: Bool
    let accountID: Int?
}

/// 可以注入内存凭据与假接口，回归测试不接触用户的 Keychain。
@MainActor
struct AccountSessionClient {
    var credentials: @MainActor () async -> AccountCredentialsSnapshot
    var save: @MainActor (BiliPassport.LoginCookies, String?) async -> Void
    var clear: @MainActor () async -> Void
    var profile: @MainActor () async throws -> AccountProfilePayload

    static var live: AccountSessionClient { AccountSessionClient(
        credentials: { await DeviceIdentity.shared.accountSnapshot() },
        save: { await DeviceIdentity.shared.saveLogin($0, accessKey: $1) },
        clear: { await DeviceIdentity.shared.clearLoginCookies() },
        profile: { try await BiliAPI.myProfile() }
    ) }
}

@MainActor
@Observable
final class AccountStore {
    struct Profile: Equatable, Codable, Sendable {
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
    private(set) var accountID: Int?
    private(set) var isLoggedIn = false
    private(set) var isRestoringSession = true
    private(set) var isRefreshingProfile = false
    private(set) var sessionError: String?
    private(set) var sessionID = UUID()

    private let client: AccountSessionClient
    private let defaults: UserDefaults
    private let likeStore: VideoLikeStore
    private var refreshID = UUID()
    private var didStartRestoring = false
    @ObservationIgnored private var networkMonitor: NWPathMonitor?
    private static let profileKey = "neobili.cachedAccountProfile"

    init(client: AccountSessionClient = .live, defaults: UserDefaults = .standard,
         likeStore: VideoLikeStore = .shared, monitorNetwork: Bool = true) {
        self.client = client
        self.defaults = defaults
        self.likeStore = likeStore
        if monitorNetwork {
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in
                guard path.status == .satisfied else { return }
                Task { @MainActor [weak self] in await self?.retrySessionIfNeeded() }
            }
            monitor.start(queue: DispatchQueue(label: "com.neobili.account.network"))
            networkMonitor = monitor
        }
    }

    deinit { networkMonitor?.cancel() }

    func restoreSessionIfNeeded() async {
        guard !didStartRestoring else { return }
        didStartRestoring = true
        let session = sessionID
        let snapshot = await client.credentials()
        guard sessionID == session else { return }
        defer { if sessionID == session { isRestoringSession = false } }
        guard snapshot.hasCredentials else {
            defaults.removeObject(forKey: Self.profileKey)
            return
        }
        isLoggedIn = true
        accountID = snapshot.accountID
        if let data = defaults.data(forKey: Self.profileKey),
           let cached = try? JSONDecoder().decode(Profile.self, from: data),
           cached.mid == snapshot.accountID {
            profile = cached
        }
        await refreshProfile()
    }

    func retrySessionIfNeeded() async {
        guard isLoggedIn, !isRestoringSession, sessionError != nil || profile == nil else { return }
        await refreshProfile()
    }

    func refreshProfile() async {
        guard isLoggedIn, !isRefreshingProfile else { return }
        let session = sessionID
        let request = UUID()
        refreshID = request
        isRefreshingProfile = true
        defer { if refreshID == request { isRefreshingProfile = false } }
        do {
            let payload = try await client.profile()
            guard sessionID == session, refreshID == request, !Task.isCancelled else { return }
            if payload.isLogin == false {
                await logout()
            } else if payload.isLogin == true, let mid = payload.mid, let name = payload.uname {
                guard accountID == nil || accountID == mid else {
                    sessionError = "账号信息暂未同步，请重试"
                    return
                }
                accountID = mid
                let loaded = Profile(mid: mid, name: name, face: payload.face,
                                     level: payload.levelInfo?.currentLevel ?? 0,
                                     coins: payload.money ?? 0, isVIP: (payload.vipStatus ?? 0) == 1)
                profile = loaded
                defaults.set(try? JSONEncoder().encode(loaded), forKey: Self.profileKey)
                sessionError = nil
            } else {
                sessionError = "账号信息暂时无法加载，请重试"
            }
        } catch {
            guard sessionID == session, refreshID == request, !error.isCancellation else { return }
            if case BiliAPIError.apiError(let code, _) = error, code == -101 {
                await logout()
            } else {
                sessionError = "暂时无法连接，登录信息已保留"
            }
        }
    }

    func completeLogin(_ cookies: BiliPassport.LoginCookies, accessKey: String? = nil) async {
        beginSessionChange()
        let session = sessionID
        isRestoringSession = true
        await client.save(cookies, accessKey)
        guard sessionID == session else { return }
        isLoggedIn = true
        accountID = Int(cookies.dedeUserID)
        await refreshProfile()
        if sessionID == session { isRestoringSession = false }
    }

    func logout() async {
        beginSessionChange()
        await client.clear()
    }

    private func beginSessionChange() {
        sessionID = UUID()
        refreshID = UUID()
        isRefreshingProfile = false
        isRestoringSession = false
        isLoggedIn = false
        accountID = nil
        profile = nil
        sessionError = nil
        defaults.removeObject(forKey: Self.profileKey)
        likeStore.resetSession()
    }
}
