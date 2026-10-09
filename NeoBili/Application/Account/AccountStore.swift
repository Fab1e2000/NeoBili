import Foundation
import SwiftUI
import Network
import Combine

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
    /// 有没有 App 登录凭据（access_key）。App 推荐按账号个性化、点踩和不感兴趣都要靠它。
    private(set) var hasAppCredential = false
    private(set) var needsAppReauthorization = false
    private(set) var isExchangingAppCredential = false
    private(set) var appCredentialError: String?
    private(set) var isRestoringSession = true
    private(set) var isRefreshingProfile = false
    private(set) var sessionError: String?
    private(set) var sessionID = UUID()

    private let client: AccountSessionClient
    private let defaults: UserDefaults
    private let likeStore: VideoLikeStore
    private var refreshID = UUID()
    private var didStartRestoring = false
    @ObservationIgnored private var credentialObserver: AnyCancellable?
    @ObservationIgnored private var networkMonitor: NWPathMonitor?
    private static let profileKey = "neobili.cachedAccountProfile"

    init(client: AccountSessionClient = .live, defaults: UserDefaults = .standard,
         likeStore: VideoLikeStore = .shared, monitorNetwork: Bool = true) {
        self.client = client
        self.defaults = defaults
        self.likeStore = likeStore
        credentialObserver = NotificationCenter.default.publisher(for: .appCredentialStateDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in await self?.refreshAppCredentialState() }
            }
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
        hasAppCredential = snapshot.hasAppCredential
        needsAppReauthorization = snapshot.needsAppReauthorization
        if let data = defaults.data(forKey: Self.profileKey),
           let cached = try? JSONDecoder().decode(Profile.self, from: data),
           cached.mid == snapshot.accountID {
            profile = cached
        }
        isRestoringSession = false
        await refreshProfile()

    }

    /// Renewal can finish after account restoration; update the existing observed store.
    func refreshAppCredentialState() async {
        let session = sessionID
        let snapshot = await client.credentials()
        guard sessionID == session, isLoggedIn, accountID == snapshot.accountID else { return }
        hasAppCredential = snapshot.hasAppCredential
        needsAppReauthorization = snapshot.needsAppReauthorization
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
                    sessionError = String(localized: "账号信息暂未同步，请重试")
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
                sessionError = String(localized: "账号信息暂时无法加载，请重试")
            }
        } catch {
            guard sessionID == session, refreshID == request, !error.isCancellation else { return }
            if case BiliAPIError.apiError(let code, _) = error, code == -101 {
                await logout()
            } else {
                sessionError = String(localized: "暂时无法连接，登录信息已保留")
            }
        }
    }

    func completeLogin(_ cookies: LoginModels.LoginCookies, accessKey: String? = nil) async {
        beginSessionChange()
        let session = sessionID
        isRestoringSession = true
        await client.save(cookies, accessKey)
        guard sessionID == session else { return }
        isLoggedIn = true
        accountID = Int(cookies.dedeUserID)
        hasAppCredential = accessKey?.isEmpty == false
        await refreshProfile()
        guard sessionID == session else { return }
        isRestoringSession = false
    }

    /// 只有 Cookie 时换一份 App 凭据。返回失败原因；成功或已有凭据时返回 nil。
    @discardableResult
    func ensureAppCredential() async -> String? {
        guard isLoggedIn, !hasAppCredential, !isExchangingAppCredential else { return nil }
        let session = sessionID
        isExchangingAppCredential = true
        appCredentialError = nil
        defer { if sessionID == session { isExchangingAppCredential = false } }
        do {
            try await client.exchangeAppCredential()
            guard sessionID == session else { return nil }
            hasAppCredential = true
            needsAppReauthorization = false
            return nil
        } catch {
            guard sessionID == session, !(error is CancellationError) else { return nil }
            let message = LoginModels.failureText(for: error)
            appCredentialError = message
            return message
        }
    }

    func completeSMSLogin(_ value: SMSLoginModels.Credentials, expectedSessionID: UUID,
                          expectedIdentitySession: UUID, authorizationOnly: Bool) async throws {
        guard sessionID == expectedSessionID else { throw CancellationError() }
        if authorizationOnly {
            guard isLoggedIn, accountID == Int(value.cookies.dedeUserID) else {
                throw LoginModels.PassportError.rejected(String(localized: "请使用当前账号的手机号授权"))
            }
        }
        if let saveSMS = client.saveSMS {
            try await saveSMS(value, expectedIdentitySession, authorizationOnly)
            guard sessionID == expectedSessionID else { throw CancellationError() }
            if !authorizationOnly { beginSessionChange() }
            isLoggedIn = true; accountID = Int(value.cookies.dedeUserID)
            hasAppCredential = true; needsAppReauthorization = false; appCredentialError = nil
            await refreshProfile()
        } else if authorizationOnly {
            try await completeAppAuthorization(value.cookies, accessKey: value.accessKey, expectedSessionID: expectedSessionID)
        } else { await completeLogin(value.cookies, accessKey: value.accessKey) }
    }

    /// 补授权只保存同账号的 App token，不清 Cookie，也不切换账号。
    func completeAppAuthorization(_ cookies: LoginModels.LoginCookies, accessKey: String?,
                                  expectedSessionID: UUID) async throws {
        guard sessionID == expectedSessionID, isLoggedIn,
              let mid = accountID, Int(cookies.dedeUserID) == mid else {
            throw LoginModels.PassportError.rejected(String(localized: "请使用当前账号的手机号授权"))
        }
        guard let accessKey, !accessKey.isEmpty else { throw BiliAPIError.missingAccessKey }
        try await client.saveAppAuthorization(accessKey, mid)
        guard sessionID == expectedSessionID else { throw CancellationError() }
        hasAppCredential = true
        needsAppReauthorization = false
        appCredentialError = nil
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
        hasAppCredential = false
        needsAppReauthorization = false
        appCredentialError = nil
        isExchangingAppCredential = false
        profile = nil
        sessionError = nil
        defaults.removeObject(forKey: Self.profileKey)
        likeStore.resetSession()
    }
}
