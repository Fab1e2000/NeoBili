import Foundation
import CryptoKit
import Synchronization

/// Manages the anonymous device identity (buvid3/buvid4) that Bilibili's web
/// API expects as a cookie on every request, even for guest (logged-out) traffic.
/// Without it, some endpoints apply stricter risk-control throttling.
///
/// 登录凭据（SESSDATA / bili_jct / DedeUserID）也走这里拼进同一个 Cookie 头：
/// 拿到之后所有接口——推荐、评论、收藏、历史——不需要任何额外改动就能获得
/// 登录态。凭据本体存 Keychain（见 `KeychainStore`），重启 App 后自动恢复。
actor DeviceIdentity {
    static let shared = DeviceIdentity(credentials: AppNetwork.isRegression ? .memory() : .keychain,
                                       allowsNetwork: !AppNetwork.isRegression)

    private let defaults: UserDefaults
    private let credentials: CredentialStorage
    private let allowsNetwork: Bool
    private let purgeCookies: @Sendable () -> Void
    private let buvid3Key = "neobili.buvid3"
    private let buvid4Key = "neobili.buvid4"
    private static let sessdataKeychainKey = "neobili.sessdata"
    private static let biliJctKeychainKey = "neobili.bili_jct"
    private static let dedeUserIDKeychainKey = "neobili.dedeuserid"
    private static let accessKeyKeychainKey = "neobili.access_key"
    private static let accessKeyClientKey = "neobili.access_key.client"
    private static let telemetryEpochKey = "neobili.telemetry.loginEpoch"

    private var cachedBuvid3: String?
    private var cachedBuvid4: String?
    private var cachedSessdata: String?
    private var cachedBiliJct: String?
    private var cachedDedeUserID: String?
    private var cachedAccessKey: String?
    private var needsAppCredentialMigration = false
    private var fetchTask: Task<Void, Never>?
    private var appSessionID = String(format: "%08x", UInt32.random(in: 0...UInt32.max))
    /// Independent process-start identifier; ordinary background/foreground keeps it.
    private let appStartSessionID: String
    private nonisolated let credentialSessionID = Mutex(UUID())

    /// 播放器在创建时同步绑定会话，不能等异步任务调度后才读取账号。
    nonisolated var loginSessionID: UUID { credentialSessionID.withLock { $0 } }

    /// Cookie、CSRF 和会话版本必须在同一次 actor 调用中读取。
    /// 排队中的写请求绑定这个版本，退出后即使重登同一个账号也不会误发。
    struct AuthenticatedRequestSnapshot: Sendable {
        let sessionID: UUID
        let accountID: Int?
        let csrfToken: String?
        let cookieHeader: String
        let isLoggedIn: Bool
    }

    func authenticatedRequestSnapshot() -> AuthenticatedRequestSnapshot {
        AuthenticatedRequestSnapshot(
            sessionID: loginSessionID,
            accountID: cachedDedeUserID.flatMap(Int.init),
            csrfToken: cachedBiliJct,
            cookieHeader: cookieHeader(),
            isLoggedIn: cachedSessdata != nil
        )
    }

    init(defaults: UserDefaults = .standard,
         credentials: CredentialStorage = AppNetwork.isRegression ? .memory() : .keychain,
         allowsNetwork: Bool = !AppNetwork.isRegression,
         purgeCookies: @escaping @Sendable () -> Void = { DeviceIdentity.purgeSharedCookieJar() }) {
        var startSession = String(format: "%08x", UInt32.random(in: 0...UInt32.max))
        while startSession == appSessionID { startSession = String(format: "%08x", UInt32.random(in: 0...UInt32.max)) }
        appStartSessionID = startSession
        self.defaults = defaults
        self.credentials = credentials
        self.allowsNetwork = allowsNetwork
        self.purgeCookies = purgeCookies
        if credentials.read(Self.telemetryEpochKey) == nil {
            credentials.write(UUID().uuidString, Self.telemetryEpochKey)
        }
        cachedBuvid3 = defaults.string(forKey: buvid3Key)
        cachedBuvid4 = defaults.string(forKey: buvid4Key)
        cachedSessdata = credentials.read(Self.sessdataKeychainKey)
        cachedBiliJct = credentials.read(Self.biliJctKeychainKey)
        cachedDedeUserID = credentials.read(Self.dedeUserIDKeychainKey)
        // 不同 scope 的旧凭据来自 Android/HD；保留 Cookie，由 AccountStore 换取 iOS 凭据。
        if credentials.read(Self.accessKeyClientKey) == AppClientIdentity.credentialScope {
            cachedAccessKey = credentials.read(Self.accessKeyKeychainKey)
        } else {
            needsAppCredentialMigration = credentials.read(Self.accessKeyKeychainKey)?.isEmpty == false
        }
    }

    func accountSnapshot() -> AccountCredentialsSnapshot {
        AccountCredentialsSnapshot(hasCredentials: cachedSessdata != nil,
                                   hasAppCredential: cachedAccessKey?.isEmpty == false,
                                   needsAppCredentialMigration: needsAppCredentialMigration,
                                   accountID: cachedDedeUserID.flatMap(Int.init))
    }

    func saveLogin(_ cookies: BiliPassport.LoginCookies, accessKey: String?) {
        setLoginCookies(sessdata: cookies.sessdata, biliJct: cookies.biliJct, dedeUserID: cookies.dedeUserID)
        setAccessKey(accessKey)
    }

    /// 当前是否带着可用的登录凭据（只看本地有没有 Cookie，不验证有效性）。
    var isLoggedIn: Bool {
        cachedSessdata != nil
    }

    /// POST 类写操作（取消收藏、删除历史等）要求的 csrf 令牌，即 bili_jct。
    var csrfToken: String? {
        cachedBiliJct
    }

    /// APP 端接口（app.bilibili.com）的凭据。短信 App 登录可同时获取它，
    /// 旧 Cookie-only 会话可能为 nil。
    var accessKey: String? {
        cachedAccessKey
    }

    /// 当前登录的 Cookie 凭据；用来换取 App 凭据。
    func loginCookies() -> BiliPassport.LoginCookies? {
        guard let cachedSessdata, let cachedBiliJct, let cachedDedeUserID else { return nil }
        return BiliPassport.LoginCookies(sessdata: cachedSessdata, biliJct: cachedBiliJct, dedeUserID: cachedDedeUserID)
    }

    /// App 接口的身份：access_key 与登录账号的 mid，在同一次 actor 调用里读出。
    typealias AppRequestAccount = AppAccountSnapshot

    func appAccount() -> AppRequestAccount {
        let key = cachedAccessKey.flatMap { $0.isEmpty ? nil : $0 }
        return AppRequestAccount(accessKey: key,
                                 mid: cachedSessdata == nil ? nil : cachedDedeUserID.flatMap(Int.init),
                                 sessionID: loginSessionID)
    }

    /// PiliPlus 的 App buvid 与网页 buvid3 分开持久化，不随刷新重建。
    func appBuvid() -> String {
        #if DEBUG
        if !AppNetwork.isRegression, let override = defaults.string(forKey: RecommendationExperiment.buvidKey), !override.isEmpty { return override }
        #endif
        let key = "neobili.appBuvid"
        if let saved = defaults.string(forKey: key), !saved.isEmpty { return saved }
        let digest = Insecure.MD5.hash(data: Data(UUID().uuidString.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let chars = Array(digest)
        let value = "XY\(chars[2])\(chars[12])\(chars[22])\(digest)"
        defaults.set(value, forKey: key)
        return value
    }

    /// 推荐和观看反馈共享本次启动/登录会话，换号（包括同账号重登）时更新。
    func appRequestHeaders(expectedSessionID: UUID) throws -> [String: String] {
        guard expectedSessionID == loginSessionID else { throw CancellationError() }
        return AppDeviceProtocol.headers(buvid: appBuvid(), sessionID: appSessionID)
    }

    func appDeviceSnapshot(expectedSessionID: UUID) throws -> AppDeviceSnapshot {
        guard expectedSessionID == loginSessionID else { throw CancellationError() }
        return .init(buvid: appBuvid(), requestSession: appSessionID,
                     startSession: appStartSessionID, mid: appAccount().mid,
                     accountEpoch: credentials.read(Self.telemetryEpochKey) ?? "",
                     model: AppClientIdentity.deviceName, version: AppClientIdentity.version,
                     build: AppClientIdentity.build)
    }

    /// App 启动时就把设备标识取回来，之后的接口请求不必再等它。
    nonisolated func warmUp() {
        Task { await startFetchIfNeeded() }
    }

    /// Cookie header value carrying whatever device identity we currently have.
    ///
    /// 第一次还没有标识时只在后台补取，不阻塞调用方：这个 SPI 请求过去会排在
    /// 视频详情和播放地址前面，直接推迟首帧。没有标识的访客请求依然可用，
    /// 只是更容易被限流，等下一次请求带上就行。
    func cookieHeader() -> String {
        if cachedBuvid3 == nil {
            startFetchIfNeeded()
        }
        var parts: [String] = []
        if let sessdata = cachedSessdata { parts.append("SESSDATA=\(sessdata)") }
        if let biliJct = cachedBiliJct { parts.append("bili_jct=\(biliJct)") }
        if let dedeUserID = cachedDedeUserID { parts.append("DedeUserID=\(dedeUserID)") }
        if let b3 = cachedBuvid3 { parts.append("buvid3=\(b3)") }
        if let b4 = cachedBuvid4 { parts.append("buvid4=\(b4)") }
        return parts.joined(separator: "; ")
    }

    /// 登录成功后写入凭据。SESSDATA 的值本来就是 URL 转义过的
    ///（含 %2C 等），原样存、原样发即可，不要再做一次编解码。
    func setLoginCookies(sessdata: String, biliJct: String, dedeUserID: String) {
        credentialSessionID.withLock { $0 = UUID() }
        credentials.write(UUID().uuidString, Self.telemetryEpochKey)
        appSessionID = String(format: "%08x", UInt32.random(in: 0...UInt32.max))
        cachedSessdata = sessdata
        cachedBiliJct = biliJct
        cachedDedeUserID = dedeUserID
        credentials.write(sessdata, Self.sessdataKeychainKey)
        credentials.write(biliJct, Self.biliJctKeychainKey)
        credentials.write(dedeUserID, Self.dedeUserIDKeychainKey)
    }

    /// App 登录返回的凭据；旧 Cookie-only 会话可缺少此值。
    func setAccessKey(_ accessKey: String?) {
        cachedAccessKey = accessKey
        needsAppCredentialMigration = false
        credentials.write(nil, Self.accessKeyClientKey)
        credentials.write(accessKey, Self.accessKeyKeychainKey)
        credentials.write(accessKey?.isEmpty == false ? AppClientIdentity.credentialScope : nil, Self.accessKeyClientKey)
    }

    /// 换取到的 App 凭据只在仍是同一账号时保存，换取途中退出或换号就丢弃。
    func setAccessKey(_ accessKey: String, forAccount dedeUserID: String, expectedSessionID: UUID? = nil) -> Bool {
        guard cachedSessdata != nil, cachedDedeUserID == dedeUserID,
              expectedSessionID == nil || expectedSessionID == loginSessionID else { return false }
        setAccessKey(accessKey)
        return true
    }

    /// 退出登录或凭据失效时清除。
    func clearLoginCookies() {
        credentialSessionID.withLock { $0 = UUID() }
        credentials.write(UUID().uuidString, Self.telemetryEpochKey)
        appSessionID = String(format: "%08x", UInt32.random(in: 0...UInt32.max))
        cachedSessdata = nil
        cachedBiliJct = nil
        cachedDedeUserID = nil
        cachedAccessKey = nil
        needsAppCredentialMigration = false
        credentials.write(nil, Self.sessdataKeychainKey)
        credentials.write(nil, Self.biliJctKeychainKey)
        credentials.write(nil, Self.dedeUserIDKeychainKey)
        credentials.write(nil, Self.accessKeyKeychainKey)
        credentials.write(nil, Self.accessKeyClientKey)
        purgeCookies()
    }

    /// 把系统共享 Cookie 罐里的 B 站 Cookie 也删掉。
    ///
    /// 登录接口的响应带着 `Set-Cookie`，URLSession 会顺手把它们存进
    /// `HTTPCookieStorage.shared`。我们自己只清 Keychain 的话，共享罐里那份
    /// SESSDATA 还在，退出登录就不彻底：界面已经是未登录，请求却仍可能带着
    /// 旧会话出去，重新登录时新旧凭据还会撞在一起。
    static func purgeSharedCookieJar() {
        let storage = HTTPCookieStorage.shared
        for cookie in storage.cookies ?? [] where cookie.domain.contains("bilibili.com") {
            storage.deleteCookie(cookie)
        }
    }

    private func startFetchIfNeeded() {
        guard allowsNetwork, fetchTask == nil else { return }
        fetchTask = Task { [weak self] in
            await self?.fetchFromSPI()
        }
    }

    private struct SPIResponse: Decodable {
        struct Data: Decodable {
            /// 接口返回的键名是 `b_3` / `b_4`，不是 `b3` / `b4`。
            /// 之前写错导致设备标识一直取不到，所有请求都在没有 buvid 的情况下发出。
            let b3: String?
            let b4: String?

            enum CodingKeys: String, CodingKey {
                case b3 = "b_3"
                case b4 = "b_4"
            }
        }
        let code: Int
        let data: Data?
    }

    private func fetchFromSPI() async {
        // 失败时清空任务，下一次请求可以重新尝试，而不是永远停在没有标识的状态。
        defer { fetchTask = nil }
        guard let url = URL(string: "https://api.bilibili.com/x/frontend/finger/spi") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(BiliHeaders.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(BiliHeaders.referer, forHTTPHeaderField: "Referer")
        do {
            let (data, _) = try await AppNetwork.session.data(for: request)
            let decoded = try JSONDecoder().decode(SPIResponse.self, from: data)
            if let b3 = decoded.data?.b3 {
                cachedBuvid3 = b3
                defaults.set(b3, forKey: buvid3Key)
            }
            if let b4 = decoded.data?.b4 {
                cachedBuvid4 = b4
                defaults.set(b4, forKey: buvid4Key)
            }
        } catch {
            // Guest browsing still works without a device id, just with a higher
            // chance of being rate-limited. Nothing to recover here.
        }
    }
}
