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

    private var cachedBuvid3: String?
    private var cachedBuvid4: String?
    private var cachedSessdata: String?
    private var cachedBiliJct: String?
    private var cachedDedeUserID: String?
    private var cachedAccessKey: String?
    private var fetchTask: Task<Void, Never>?
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
        self.defaults = defaults
        self.credentials = credentials
        self.allowsNetwork = allowsNetwork
        self.purgeCookies = purgeCookies
        cachedBuvid3 = defaults.string(forKey: buvid3Key)
        cachedBuvid4 = defaults.string(forKey: buvid4Key)
        cachedSessdata = credentials.read(Self.sessdataKeychainKey)
        cachedBiliJct = credentials.read(Self.biliJctKeychainKey)
        cachedDedeUserID = credentials.read(Self.dedeUserIDKeychainKey)
        cachedAccessKey = credentials.read(Self.accessKeyKeychainKey)
    }

    func accountSnapshot() -> AccountCredentialsSnapshot {
        AccountCredentialsSnapshot(hasCredentials: cachedSessdata != nil,
                                   hasAppCredential: cachedAccessKey?.isEmpty == false,
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

    /// APP 端接口（app.bilibili.com）的凭据。只有扫码登录能拿到它，
    /// 网页密码登录只有 Cookie，所以这里可能为 nil。
    var accessKey: String? {
        cachedAccessKey
    }

    /// 当前登录的 Cookie 凭据；用来换取 App 凭据。
    func loginCookies() -> BiliPassport.LoginCookies? {
        guard let cachedSessdata, let cachedBiliJct, let cachedDedeUserID else { return nil }
        return BiliPassport.LoginCookies(sessdata: cachedSessdata, biliJct: cachedBiliJct, dedeUserID: cachedDedeUserID)
    }

    /// App 接口的身份：access_key 与登录账号的 mid，在同一次 actor 调用里读出。
    struct AppRequestAccount: Sendable {
        let accessKey: String?
        let mid: Int?
        let sessionID: UUID
    }

    func appAccount() -> AppRequestAccount {
        let key = cachedAccessKey.flatMap { $0.isEmpty ? nil : $0 }
        return AppRequestAccount(accessKey: key,
                                 mid: cachedSessdata == nil ? nil : cachedDedeUserID.flatMap(Int.init),
                                 sessionID: loginSessionID)
    }

    /// PiliPlus 的 App buvid 与网页 buvid3 分开持久化，不随刷新重建。
    func appBuvid() -> String {
        let key = "neobili.appBuvid"
        if let saved = defaults.string(forKey: key), !saved.isEmpty { return saved }
        let digest = Insecure.MD5.hash(data: Data(UUID().uuidString.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let chars = Array(digest)
        let value = "XY\(chars[2])\(chars[12])\(chars[22])\(digest)"
        defaults.set(value, forKey: key)
        return value
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

    /// 扫码或密码登录成功后写入凭据。SESSDATA 的值本来就是 URL 转义过的
    ///（含 %2C 等），原样存、原样发即可，不要再做一次编解码。
    func setLoginCookies(sessdata: String, biliJct: String, dedeUserID: String) {
        credentialSessionID.withLock { $0 = UUID() }
        cachedSessdata = sessdata
        cachedBiliJct = biliJct
        cachedDedeUserID = dedeUserID
        credentials.write(sessdata, Self.sessdataKeychainKey)
        credentials.write(biliJct, Self.biliJctKeychainKey)
        credentials.write(dedeUserID, Self.dedeUserIDKeychainKey)
    }

    /// 扫码登录额外带回来的 APP 端凭据。密码登录没有这个值，传 nil 即可。
    func setAccessKey(_ accessKey: String?) {
        cachedAccessKey = accessKey
        credentials.write(accessKey, Self.accessKeyKeychainKey)
    }

    /// 换取到的 App 凭据只在仍是同一账号时保存，换取途中退出或换号就丢弃。
    func setAccessKey(_ accessKey: String, forAccount dedeUserID: String) -> Bool {
        guard cachedSessdata != nil, cachedDedeUserID == dedeUserID else { return false }
        setAccessKey(accessKey)
        return true
    }

    /// 退出登录或凭据失效时清除。
    func clearLoginCookies() {
        credentialSessionID.withLock { $0 = UUID() }
        cachedSessdata = nil
        cachedBiliJct = nil
        cachedDedeUserID = nil
        cachedAccessKey = nil
        credentials.write(nil, Self.sessdataKeychainKey)
        credentials.write(nil, Self.biliJctKeychainKey)
        credentials.write(nil, Self.dedeUserIDKeychainKey)
        credentials.write(nil, Self.accessKeyKeychainKey)
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

enum BiliHeaders {
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    static let referer = "https://www.bilibili.com"

    /// APP 端接口只认 BiliDroid 的 UA。带着浏览器 UA 去请求 app.bilibili.com
    /// 会被当成非法客户端，即使签名正确也拿不到数据。
    static let appUserAgent = "Mozilla/5.0 BiliDroid/2.0.1 (bbcallen@gmail.com) os/android model/android_hd mobi_app/android_hd build/2001100 channel/master innerVer/2001100 osVer/15 network/2"

    /// PiliPlus 账号拦截器给 App 请求补的头；登录后再带上 mid 和由它算出的 aurora eid。
    static func appAccountHeaders(mid: Int?) -> [String: String] {
        var headers = ["env": "prod", "app-key": "android64", "x-bili-aurora-zone": "sh001"]
        if let mid, mid > 0 {
            headers["x-bili-mid"] = String(mid)
            headers["x-bili-aurora-eid"] = auroraEID(mid: mid)
        }
        return headers
    }

    /// 与 PiliPlus IdUtils.genAuroraEid 相同：mid 的十进制字节逐位异或固定密钥，再做无填充 base64。
    static func auroraEID(mid: Int) -> String {
        let key = Array("ad1va46a7lza".utf8)
        let bytes = Array(String(mid).utf8).enumerated().map { $0.element ^ key[$0.offset % key.count] }
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }
}
