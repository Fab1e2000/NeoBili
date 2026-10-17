#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation
import CryptoKit
import Synchronization

extension Notification.Name {
    static let appCredentialStateDidChange = Notification.Name("NeoBili.appCredentialStateDidChange")
}

/// Manages the anonymous device identity (buvid3/buvid4) that Bilibili's web
/// API expects as a cookie on every request, even for guest (logged-out) traffic.
/// Without it, some endpoints apply stricter risk-control throttling.
///
/// 登录凭据（SESSDATA / bili_jct / DedeUserID）也走这里拼进同一个 Cookie 头：
/// 拿到之后所有接口——推荐、评论、收藏、历史——不需要任何额外改动就能获得
/// 登录态。凭据本体存 Keychain（见 `KeychainStore`），重启 App 后自动恢复。
actor DeviceIdentity {

    private let defaults: UserDefaults
    private let eventSerialDefaults: UserDefaults
    private let credentials: CredentialStorage
    private let accountPersistence: AccountCredentialPersistence
    private let rawTransport: SMSPassport.Transport
    private nonisolated let networkSnapshot: @Sendable () -> AppNetworkMetadataSnapshot
    private let allowsNetwork: Bool
    private let purgeCookies: @Sendable () -> Void
    private let buvid3Key = "neobili.buvid3"
    private let buvid4Key = "neobili.buvid4"
    private var renewableLogin: SMSLoginModels.Credentials?
    private var renewalTask: Task<Void, Never>?
    private var renewalTaskID: UUID?
    private var nextRenewalCheck: TimeInterval = 0
    private(set) var renewalState = "idle"
    private var appCredentialRejected = false

    // Actor-owned mirror: event snapshots must not perform a Keychain IPC per card.
    private var cachedTelemetryEpoch: String?
    private var cachedBuvid3: String?
    private var cachedBuvid4: String?
    private var cachedSessdata: String?
    private var cachedBiliJct: String?
    private var cachedDedeUserID: String?
    private var cachedAccessKey: String?
    private var needsAppCredentialMigration = false
    private var fetchTask: Task<Void, Never>?
    private var transientAppBuvid: String?
    private let experimentalBuvid: String?
    private let customBuvid: String?
    private let vendorIdentifier: @Sendable () async -> String?
    private let deviceRegistration: AppDeviceRegistration?
    private let guestRegistration: AppGuestRegistration?
    private let ticketService: AppTicketService?
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
         randomBuvidExperiment: Bool = false,
         customBuvid: String? = nil,
         credentials: CredentialStorage = AppNetwork.isRegression ? .memory() : .keychain,
         allowsNetwork: Bool = !AppNetwork.isRegression,
         eventSerialDefaults: UserDefaults? = nil,
         vendorIdentifier: @escaping @Sendable () async -> String? = { await AppBuvid.vendorIdentifier() },
         deviceRegistration: AppDeviceRegistration? = nil,
         guestRegistration: AppGuestRegistration? = nil,
         ticketService: AppTicketService? = nil,
         rawTransport: @escaping SMSPassport.Transport = { try await AppNetwork.session.data(for: $0) },
         networkSnapshot: @escaping @Sendable () -> AppNetworkMetadataSnapshot = { AppNetworkMetadata.shared.snapshot() },
         purgeCookies: @escaping @Sendable () -> Void = { DeviceIdentity.purgeSharedCookieJar() }) {
        var startSession = String(format: "%08x", UInt32.random(in: 0...UInt32.max))
        while startSession == appSessionID { startSession = String(format: "%08x", UInt32.random(in: 0...UInt32.max)) }
        appStartSessionID = startSession
        self.defaults = defaults
        self.eventSerialDefaults = eventSerialDefaults ?? defaults
        // Preserve the installation sequence across upgrade. Event writes belong
        // to their own domain, separate from standard AppStorage preferences.
        let serialKey = "neobili.neuron.eventSerial"
        if let eventSerialDefaults, eventSerialDefaults.object(forKey: serialKey) == nil {
            eventSerialDefaults.set(defaults.integer(forKey: serialKey), forKey: serialKey)
        }
        self.credentials = credentials
        self.accountPersistence = AccountCredentialPersistence(storage: credentials, scope: AppClientIdentity.credentialScope)
        self.customBuvid = customBuvid.flatMap(DeviceIdentityPreferences.normalizedCustomBuvid)
        self.experimentalBuvid = randomBuvidExperiment
            ? AppBuvid.randomExperimentIdentifier(defaults: defaults, credentials: credentials) : nil
        let ownRegistrationCredentials = self.customBuvid.map { AppBuvid.customRegistrationStorage(credentials, buvid: $0) }
            ?? (randomBuvidExperiment ? AppBuvid.experimentRegistrationStorage(credentials) : credentials)
        let capturedDevice = CapturedDeviceDiagnostic.configuration
        let registrationCredentials = capturedDevice.map { CapturedDeviceDiagnostic.isolatedStorage(credentials, configuration: $0) }
            ?? ownRegistrationCredentials
        self.rawTransport = rawTransport
        self.networkSnapshot = networkSnapshot
        self.allowsNetwork = allowsNetwork
        self.vendorIdentifier = vendorIdentifier
        self.deviceRegistration = deviceRegistration ?? (allowsNetwork ? AppDeviceRegistration(credentials: registrationCredentials, transport: rawTransport) : nil)
        self.guestRegistration = guestRegistration ?? (allowsNetwork ? AppGuestRegistration(credentials: registrationCredentials, transport: rawTransport,
            capturedGuestID: capturedDevice?.parsedGuestID) : nil)
        self.ticketService = ticketService ?? (allowsNetwork ? AppTicketService(credentials: registrationCredentials, transport: rawTransport) : nil)
        self.purgeCookies = purgeCookies
        cachedTelemetryEpoch = accountPersistence.restoreTelemetryEpoch()
        cachedBuvid3 = defaults.string(forKey: buvid3Key)
        cachedBuvid4 = defaults.string(forKey: buvid4Key)
        let restored = accountPersistence.restoreLogin(telemetryEpoch: cachedTelemetryEpoch)
        cachedTelemetryEpoch = restored.telemetryEpoch
        cachedSessdata = restored.sessdata
        cachedBiliJct = restored.csrf
        cachedDedeUserID = restored.accountID
        cachedAccessKey = restored.accessKey
        needsAppCredentialMigration = restored.needsMigration
        renewableLogin = restored.renewableLogin
    }

    func accountSnapshot() -> AccountCredentialsSnapshot {
        AccountCredentialsSnapshot(hasCredentials: cachedSessdata != nil,
                                   hasAppCredential: cachedAccessKey?.isEmpty == false && !appCredentialRejected,
                                   needsAppReauthorization: appCredentialRejected,
                                   needsAppCredentialMigration: needsAppCredentialMigration,
                                   accountID: cachedDedeUserID.flatMap(Int.init))
    }

    func saveLogin(_ cookies: LoginModels.LoginCookies, accessKey: String?) async {
        let oldEpoch = cachedTelemetryEpoch ?? ""
        replaceLoginCookies(sessdata: cookies.sessdata, biliJct: cookies.biliJct, dedeUserID: cookies.dedeUserID)
        setAccessKey(accessKey)
        await ticketService?.invalidateAccount(prefix: oldEpoch + "|")
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
        appCredentialRejected ? nil : cachedAccessKey
    }

    /// 当前登录的 Cookie 凭据；用来换取 App 凭据。
    func loginCookies() -> LoginModels.LoginCookies? {
        guard let cachedSessdata, let cachedBiliJct, let cachedDedeUserID else { return nil }
        return LoginModels.LoginCookies(sessdata: cachedSessdata, biliJct: cachedBiliJct, dedeUserID: cachedDedeUserID)
    }

    /// App 接口的身份：access_key 与登录账号的 mid，在同一次 actor 调用里读出。
    typealias AppRequestAccount = AppAccountSnapshot

    func appAccount() -> AppRequestAccount {
        let key = accessKey.flatMap { $0.isEmpty ? nil : $0 }
        return AppRequestAccount(accessKey: key,
                                 mid: cachedSessdata == nil ? nil : cachedDedeUserID.flatMap(Int.init),
                                 sessionID: loginSessionID)
    }

    /// Own local identity, separate from server device_id and web buvid3.
    func appBuvid() async -> String {
        if let captured = CapturedDeviceDiagnostic.configuration { return captured.buvid }
        if let customBuvid { return customBuvid }
        if let experimentalBuvid { return experimentalBuvid }
        #if DEBUG
        if !AppNetwork.isRegression, let override = defaults.string(forKey: RecommendationExperiment.buvidKey), !override.isEmpty { return override }
        #endif
        let key = "neobili.appBuvid"
        if let saved = defaults.string(forKey: key), !saved.isEmpty { return saved }
        if let saved = credentials.read(key), !saved.isEmpty {
            defaults.set(saved, forKey: key); return saved
        }
        let identifier = await vendorIdentifier()
        // Actor re-entry while obtaining UIKit data must not replace a newer identity.
        if let saved = defaults.string(forKey: key), !saved.isEmpty { return saved }
        if let value = AppBuvid.generate(idfv: identifier) {
            defaults.set(value, forKey: key); credentials.write(value, key)
            return value
        }
        if let transientAppBuvid { return transientAppBuvid }
        let value = String(Int(Date().timeIntervalSince1970 * 1_000_000))
        transientAppBuvid = value
        return value
    }

    /// 推荐和观看反馈共享本次启动/登录会话，换号（包括同账号重登）时更新。
    func appRequestHeaders(expectedSessionID: UUID) async throws -> [String: String] {
        guard expectedSessionID == loginSessionID else { throw CancellationError() }
        let buvid = await appBuvid()
        guard expectedSessionID == loginSessionID else { throw CancellationError() }
        var headers = AppDeviceProtocol.headers(buvid: buvid, sessionID: appSessionID)
        headers.merge(networkSnapshot().headers) { _, new in new }
        let account = appAccount()
        let guestID = await guestRegistration?.cachedID()
        if let guestID { headers["guestid"] = String(guestID) }
        let fingerprint = await deviceRegistration?.register(buvid: buvid, mid: account.mid,
            accessKey: account.accessKey, headers: headers)
        guard expectedSessionID == loginSessionID else { throw CancellationError() }
        let device = await AppDeviceMetadata.build(buvid: buvid, guestID: guestID, fingerprint: fingerprint)
        headers["x-bili-device-bin"] = device.base64EncodedString()
        guard expectedSessionID == loginSessionID else { throw CancellationError() }
        let scope = (cachedTelemetryEpoch ?? "") + "|" + buvid
        if let ticket = await ticketService?.cachedTicket(scope: scope, headers: headers, accessKey: account.accessKey) {
            headers["x-bili-ticket"] = ticket
        }
        guard expectedSessionID == loginSessionID else { throw CancellationError() }
        return headers
    }

    func observeAppResponse(_ response: HTTPURLResponse, request: URLRequest) async {
        guard allowsNetwork, request.value(forHTTPHeaderField: "session_id") == appSessionID, let host = request.url?.host,
              ["app.bilibili.com", "api.bilibili.com", "grpc.biliapi.net", "dataflow.biliapi.com", "passport.bilibili.com"].contains(host),
              let sentTicket = request.value(forHTTPHeaderField: "x-bili-ticket") else { return }
        await ticketService?.observe(status: response.value(forHTTPHeaderField: "x-ticket-status"), sentTicket: sentTicket)
    }

    func appDeviceSnapshot(expectedSessionID: UUID) async throws -> AppDeviceSnapshot {
        guard expectedSessionID == loginSessionID else { throw CancellationError() }
        let buvid = await appBuvid()
        let fingerprint = await deviceRegistration?.cachedID(buvid: buvid)
        guard expectedSessionID == loginSessionID else { throw CancellationError() }
        return .init(buvid: buvid, requestSession: appSessionID,
                     startSession: appStartSessionID, mid: appAccount().mid,
                     accountEpoch: cachedTelemetryEpoch ?? "",
                     model: AppClientIdentity.deviceName, version: AppClientIdentity.version,
                     build: AppClientIdentity.build, fingerprint: fingerprint)
    }

    func registeredDeviceID() async -> String? {
        let buvid = await appBuvid()
        return await deviceRegistration?.cachedID(buvid: buvid)
    }

    func nextBehaviorSnapshot(expectedSessionID: UUID) async throws -> AppDeviceSnapshot {
        var snapshot = try await appDeviceSnapshot(expectedSessionID: expectedSessionID)
        guard expectedSessionID == loginSessionID else { throw CancellationError() }
        let key = "neobili.neuron.eventSerial"
        let old = eventSerialDefaults.integer(forKey: key)
        let next = old >= 0 && old < Int.max ? old + 1 : 1
        eventSerialDefaults.set(next, forKey: key)
        snapshot.eventSerial = next
        return snapshot
    }

    /// App 启动时就把设备标识取回来，之后的接口请求不必再等它。
    nonisolated func warmUp() {
        _ = networkSnapshot()
        Task {
            await startFetchIfNeeded()
            await refreshAppServices()
        }
    }

    /// Guest identity is loaded at startup/activation, never on every feed refresh.
    func refreshAppServices(validateCredential: Bool = false) async {
        guard allowsNetwork else { return }
        let session = loginSessionID
        let buvid = await appBuvid()
        let base = AppDeviceProtocol.headers(buvid: buvid, sessionID: appSessionID)
            .merging(networkSnapshot().headers) { _, new in new }
        _ = await guestRegistration?.load(buvid: buvid, headers: base)
        guard session == loginSessionID else { return }
        _ = try? await appRequestHeaders(expectedSessionID: session)
        await renewLoginIfNeeded(forceValidation: validateCredential)
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
    func setLoginCookies(sessdata: String, biliJct: String, dedeUserID: String) async {
        let oldEpoch = cachedTelemetryEpoch ?? ""
        replaceLoginCookies(sessdata: sessdata, biliJct: biliJct, dedeUserID: dedeUserID)
        await ticketService?.invalidateAccount(prefix: oldEpoch + "|")
    }

    private func replaceTelemetryEpoch(_ value: String) {
        cachedTelemetryEpoch = accountPersistence.replaceTelemetryEpoch(value)
    }

    private func replaceLoginCookies(sessdata: String, biliJct: String, dedeUserID: String) {
        discardRenewal()
        credentialSessionID.withLock { $0 = UUID() }
        replaceTelemetryEpoch(UUID().uuidString)
        appSessionID = String(format: "%08x", UInt32.random(in: 0...UInt32.max))
        cachedSessdata = sessdata
        cachedBiliJct = biliJct
        cachedDedeUserID = dedeUserID
        accountPersistence.writeLegacyCookies(sessdata: sessdata, csrf: biliJct, accountID: dedeUserID)
    }

    /// App 登录返回的凭据；旧 Cookie-only 会话可缺少此值。
    func setAccessKey(_ accessKey: String?) {
        discardRenewal()
        cachedAccessKey = accessKey
        needsAppCredentialMigration = false
        accountPersistence.writeAccessKey(accessKey)
    }

    /// 换取到的 App 凭据只在仍是同一账号时保存，换取途中退出或换号就丢弃。
    func setAccessKey(_ accessKey: String, forAccount dedeUserID: String, expectedSessionID: UUID? = nil) -> Bool {
        guard cachedSessdata != nil, cachedDedeUserID == dedeUserID,
              expectedSessionID == nil || expectedSessionID == loginSessionID else { return false }
        setAccessKey(accessKey)
        return true
    }

    /// 退出登录或凭据失效时清除。
    func clearLoginCookies() async {
        discardRenewal()
        let oldEpoch = cachedTelemetryEpoch ?? ""
        credentialSessionID.withLock { $0 = UUID() }
        replaceTelemetryEpoch(UUID().uuidString)
        appSessionID = String(format: "%08x", UInt32.random(in: 0...UInt32.max))
        cachedSessdata = nil
        cachedBiliJct = nil
        cachedDedeUserID = nil
        cachedAccessKey = nil
        needsAppCredentialMigration = false
        accountPersistence.clearLegacyLogin()
        purgeCookies()
        await ticketService?.invalidateAccount(prefix: oldEpoch + "|")
    }

    private func discardRenewal() {
        renewalTask?.cancel(); renewalTask = nil; renewalTaskID = nil
        renewableLogin = nil; nextRenewalCheck = 0; renewalState = "idle"
        appCredentialRejected = false
        accountPersistence.discardRenewal()
    }

    /// Store the SMS token pair and Cookie together, including authorization-only login.
    func saveSMSLogin(_ value: SMSLoginModels.Credentials, expectedSessionID: UUID, authorizationOnly: Bool) async throws {
        guard loginSessionID == expectedSessionID else { throw CancellationError() }
        if authorizationOnly {
            guard cachedDedeUserID == value.cookies.dedeUserID, cachedSessdata != nil else { throw CancellationError() }
        }
        // Verify the atomic record before changing live credentials. Failed writes keep the old login.
        let epoch = authorizationOnly ? (cachedTelemetryEpoch ?? UUID().uuidString) : UUID().uuidString
        try accountPersistence.saveVerifiedBundle(value, epoch: epoch)
        let oldEpoch = cachedTelemetryEpoch ?? ""
        renewalTask?.cancel(); renewalTask = nil; renewalTaskID = nil
        if !authorizationOnly {
            credentialSessionID.withLock { $0 = UUID() }
            replaceTelemetryEpoch(epoch)
            appSessionID = String(format: "%08x", UInt32.random(in: 0...UInt32.max))
        }
        applyLoginBundle(value)
        nextRenewalCheck = 0
        renewalState = value.refreshToken == nil ? "needs-login" : "ready"
        await ticketService?.invalidateAccount(prefix: oldEpoch + "|")
    }

    private func applyLoginBundle(_ value: SMSLoginModels.Credentials) {
        renewableLogin = value
        appCredentialRejected = false
        cachedSessdata = value.cookies.sessdata; cachedBiliJct = value.cookies.biliJct
        cachedDedeUserID = value.cookies.dedeUserID; cachedAccessKey = value.accessKey
        needsAppCredentialMigration = false
        // Legacy readers remain compatible; relaunch prefers the complete atomic record.
        accountPersistence.writeLegacyMirror(value)
    }

    func renewalDevice(expectedSessionID: UUID) async throws -> AppLoginRenewal.Device {
        let headers = try await appRequestHeaders(expectedSessionID: expectedSessionID)
        let buvid = await appBuvid()
        let key = "neobili.device.localBUVID"
        let local: String
        if let saved = credentials.read(key), saved.count == 64 { local = saved }
        else {
            guard let vendor = await vendorIdentifier(), !vendor.isEmpty else { throw AppLoginRenewal.Failure.malformed }
            if let saved = credentials.read(key), saved.count == 64 { local = saved }
            else {
                let firstKey = "neobili.device.firstRunMilliseconds"
                let first = credentials.read(firstKey).flatMap(Int64.init) ?? Int64(Date().timeIntervalSince1970 * 1000)
                credentials.write(String(first), firstKey)
                local = AppLocalDeviceID.generate(vendor: vendor, platform: AppClientIdentity.deviceName,
                    firstRun: first, date: Date())
                credentials.write(local, key)
            }
        }
        let registered = await registeredDeviceID()
        guard loginSessionID == expectedSessionID else { throw CancellationError() }
        return .init(buvid: buvid, localID: local, deviceID: registered ?? local,
                     name: "iPhone", platform: AppClientIdentity.deviceName, headers: headers)
    }

    /// Activation/startup only. Thirty-minute success throttle and one-minute failure backoff
    /// are local resource policy, not a claimed official schedule. No timer is created.
    func renewLoginIfNeeded(transport: AppLoginRenewal.Transport? = nil,
                            now: TimeInterval = Date().timeIntervalSince1970,
                            device suppliedDevice: AppLoginRenewal.Device? = nil,
                            forceValidation: Bool = false) async {
        guard allowsNetwork || transport != nil else { return }
        guard !appCredentialRejected else { return }
        if let renewalTask { await renewalTask.value; return }
        guard forceValidation || now >= nextRenewalCheck else { return }
        let old: SMSLoginModels.Credentials
        if let saved = renewableLogin { old = saved }
        else if let cookies = loginCookies(), let key = accessKey, !key.isEmpty {
            // Legacy/QR authorization can still be validated without inventing a refresh token.
            old = .init(cookies: cookies, accessKey: key)
        } else {
            return
        }
        let snapshot = AppLoginRenewal.Snapshot(session: loginSessionID, credentials: old)
        let id = UUID(); renewalTaskID = id
        let task = Task { await self.performRenewal(snapshot, transport: transport ?? self.rawTransport,
                                                   now: now, device: suppliedDevice) }
        renewalTask = task
        await task.value
        if renewalTaskID == id { renewalTask = nil; renewalTaskID = nil }
    }

    private func isCurrent(_ snapshot: AppLoginRenewal.Snapshot) -> Bool {
        guard loginSessionID == snapshot.session else { return false }
        if let renewableLogin { return renewableLogin == snapshot.credentials }
        return cachedAccessKey == snapshot.credentials.accessKey && loginCookies() == snapshot.credentials.cookies
    }

    private func performRenewal(_ snapshot: AppLoginRenewal.Snapshot, transport: AppLoginRenewal.Transport,
                                now: TimeInterval, device suppliedDevice: AppLoginRenewal.Device?) async {
        do {
            let device: AppLoginRenewal.Device
            if let suppliedDevice { device = suppliedDevice }
            else { device = try await renewalDevice(expectedSessionID: snapshot.session) }
            guard isCurrent(snapshot) else { return }
            let info = try await AppLoginRenewal.info(old: snapshot.credentials, device: device, transport: transport)
            guard isCurrent(snapshot) else { return }
            guard info.refresh else { nextRenewalCheck = now + 1800; renewalState = "valid"; return }
            guard snapshot.credentials.refreshToken?.isEmpty == false else {
                nextRenewalCheck = now + 1800; renewalState = "needs-login"; return
            }
            let sts = await AppLoginRenewal.serverTime(old: snapshot.credentials, device: device, transport: transport)
            guard isCurrent(snapshot) else { return }
            let fresh = try await AppLoginRenewal.refresh(old: snapshot.credentials, device: device, sts: sts, transport: transport)
            guard isCurrent(snapshot) else { return }
            try accountPersistence.saveVerifiedBundle(fresh, epoch: cachedTelemetryEpoch ?? "")
            applyLoginBundle(fresh)
            nextRenewalCheck = now + 1800; renewalState = "renewed"
            // Preserve login generation so valid playback/queued feedback survives an in-account renewal.
            // Confirm uses captured OLD credentials. Failure must never roll back the new login.
            do { try await AppLoginRenewal.confirm(old: snapshot.credentials, device: device, sts: sts, transport: transport) }
            catch {
                if loginSessionID == snapshot.session, renewableLogin == fresh { renewalState = "renewed-confirm-failed" }
            }
        } catch {
            guard isCurrent(snapshot) else { return }
            nextRenewalCheck = now + 60
            if case AppLoginRenewal.Failure.rejected(61000) = error {
                // Keep UI/account deletion under AccountStore's control; never silently cross accounts.
                renewalState = "needs-login"; nextRenewalCheck = .greatestFiniteMagnitude
                appCredentialRejected = true
                NotificationCenter.default.post(name: .appCredentialStateDidChange, object: nil)
            } else { renewalState = "retry-later" }
        }
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
            let (data, _) = try await rawTransport(request)
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
