import Foundation

/// passport.bilibili.com 上的登录端点（扫码 / 账号密码）。
///
/// 这些请求不在 api.bilibili.com 域上，所以不复用 `APIClient` 的传输层；
/// 登录成功后真正的凭据（SESSDATA 等）通过 Set-Cookie 头下发，需要从
/// HTTP 响应头里取，而不是从 JSON 里。
enum BiliPassport {
    struct LoginCookies: Equatable, Sendable {
        let sessdata: String
        let biliJct: String
        let dedeUserID: String
    }

    enum PassportError: LocalizedError, Equatable {
        case invalidResponse
        case missingCookies
        /// 服务端业务错误（密码错误、验证码失败等），带上接口原话。
        case rejected(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return String(localized: "登录服务响应异常")
            case .missingCookies: return String(localized: "登录成功但未收到凭据")
            case .rejected(let message): return message
            }
        }
    }

    private static let baseURL = URL(string: "https://passport.bilibili.com")!

    // MARK: - 扫码登录

    struct QRCodeInfo: Decodable, Sendable {
        /// 二维码内容本身，渲染成二维码图片给 B 站 App 扫。
        let url: String
        let qrcodeKey: String

        enum CodingKeys: String, CodingKey {
            case url
            case qrcodeKey = "qrcode_key"
        }
    }

    static func generateQRCode() async throws -> QRCodeInfo {
        try await get(path: "x/passport-login/web/qrcode/generate")
    }

    enum QRCodePollOutcome: Sendable {
        /// 二维码还在等待被扫。
        case waiting
        /// 已扫码，等待手机上确认。
        case scanned
        /// 二维码过期，需要重新生成。
        case expired
        /// 确认完成，拿到登录凭据。
        ///
        /// `accessKey` 只有 App 端扫码（`pollAppQRCode`）才会带回来；网页扫码
        /// 拿到的只有 Cookie，这里为 nil。见 `APIClient.postApp`。
        case confirmed(LoginCookies, accessKey: String?)
    }

    /// 轮询扫码结果。注意业务状态码在 `data.code` 里（顶层 `code` 恒为 0，
    /// 直接读顶层会把「未扫码」误判成「登录成功」）：
    /// 86101 未扫码、86090 已扫码未确认、86038 已过期、0 已确认（此刻
    /// Set-Cookie 才会带上 SESSDATA 等凭据）。
    static func pollQRCode(_ qrcodeKey: String) async throws -> QRCodePollOutcome {
        let request = try makeRequest(path: "x/passport-login/web/qrcode/poll", query: ["qrcode_key": qrcodeKey])
        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw PassportError.invalidResponse
        }
        return try pollOutcome(fromPayload: data, cookies: loginCookies(from: http))
    }

    private struct PollEnvelope: Decodable {
        let code: Int?
        let message: String?
        let data: PollData?

        struct PollData: Decodable {
            let code: Int?
            let message: String?
        }
    }

    /// 从轮询响应体解析扫码状态。cookies 传调用方从 Set-Cookie 头里取到的凭据。
    static func pollOutcome(fromPayload payload: Data, cookies: LoginCookies?) throws -> QRCodePollOutcome {
        guard let envelope = try? JSONDecoder().decode(PollEnvelope.self, from: payload) else {
            throw PassportError.invalidResponse
        }
        switch envelope.data?.code ?? envelope.code {
        case 86101:
            return .waiting
        case 86090:
            return .scanned
        case 86038:
            return .expired
        case 0:
            guard let cookies else {
                throw PassportError.missingCookies
            }
            return .confirmed(cookies, accessKey: nil)
        case let code:
            throw PassportError.rejected("\(envelope.data?.message ?? envelope.message ?? String(localized: "登录失败")) (code \(code))")
        }
    }

    // MARK: - App 端扫码登录

    /// App（iPhone）扫码登录，用来换取 `access_key`。
    ///
    /// 为什么不直接用上面的网页扫码：网页登录只下发 Cookie，而「点踩」这类接口
    /// 只存在于 app.bilibili.com 上，认的是 `access_key`（见 `APIClient.postApp`）。
    /// App 端这条扫码链路成功时，同一份 JSON 里既有 `access_token` 也有整套
    /// Cookie，一次扫码就能把两种凭据都拿齐，所以它是网页扫码的超集。
    ///
    /// 用户体验上没有区别，仍然是拿 B 站 App 扫一张二维码；手机上的确认页会
    /// 显示服务端提供的 iPhone 登录确认页。
    struct AppQRCodeInfo: Decodable, Sendable {
        let url: String
        let authCode: String

        enum CodingKeys: String, CodingKey {
            case url
            case authCode = "auth_code"
        }
    }

    static func generateAppQRCode() async throws -> AppQRCodeInfo {
        let params = AppSigner.signed(
            AppClientIdentity.parameters.merging(["local_id": "0"]) { _, value in value },
            purpose: .passport
        )
        return try await postSigned(path: "x/passport-tv-login/qrcode/auth_code", params: params)
    }

    /// 轮询 App 扫码结果。
    ///
    /// 和网页那条链路不同，这里的业务状态码在**顶层** `code` 上，凭据也在
    /// JSON body 里而不是 Set-Cookie 头里：
    /// 86039 未确认、86038 已过期、0 已确认。
    static func pollAppQRCode(_ authCode: String, fallbackCookies: LoginCookies? = nil) async throws -> QRCodePollOutcome {
        let params = AppSigner.signed(
            AppClientIdentity.parameters.merging(["auth_code": authCode, "local_id": "0"]) { _, value in value },
            purpose: .passport
        )
        guard let url = URL(string: baseURL.appendingPathComponent("x/passport-tv-login/qrcode/poll").absoluteString) else {
            throw PassportError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(BiliHeaders.appUserAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = AppSigner.queryString(from: params).data(using: .utf8)

        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw PassportError.invalidResponse
        }
        return try appPollOutcome(fromPayload: data, fallbackCookies: fallbackCookies)
    }

    private struct AppPollEnvelope: Decodable {
        let code: Int
        let message: String?
        let data: AppPollData?

        struct AppPollData: Decodable {
            let mid: Int?
            let accessToken: String?
            let cookieInfo: CookieInfo?

            enum CodingKeys: String, CodingKey {
                case mid
                case accessToken = "access_token"
                case cookieInfo = "cookie_info"
            }

            struct CookieInfo: Decodable {
                let cookies: [Cookie]?

                struct Cookie: Decodable {
                    let name: String
                    let value: String
                }
            }
        }
    }

    /// 解析 App 扫码轮询的响应体。单独拆出来是为了能脱离网络直接测。
    static func appPollOutcome(fromPayload payload: Data, fallbackCookies: LoginCookies? = nil) throws -> QRCodePollOutcome {
        guard let envelope = try? JSONDecoder().decode(AppPollEnvelope.self, from: payload) else {
            throw PassportError.invalidResponse
        }
        switch envelope.code {
        case 86039, 86090:
            // 86039 是「未确认」，它同时覆盖了网页那条链路里未扫码和已扫码两种状态。
            return .waiting
        case 86038:
            return .expired
        case 0:
            // Cookie 换凭据时响应可能只有 token；只复用已确认属于同一账号的 Cookie。
            if let fallbackCookies, envelope.data?.mid == Int(fallbackCookies.dedeUserID),
               let token = envelope.data?.accessToken, !token.isEmpty {
                return .confirmed(fallbackCookies, accessKey: token)
            }
            var values: [String: String] = [:]
            for cookie in envelope.data?.cookieInfo?.cookies ?? [] {
                values[cookie.name] = cookie.value
            }
            guard let sessdata = values["SESSDATA"],
                  let biliJct = values["bili_jct"],
                  let dedeUserID = values["DedeUserID"]
            else {
                throw PassportError.missingCookies
            }
            let cookies = LoginCookies(sessdata: sessdata, biliJct: biliJct, dedeUserID: dedeUserID)
            if let mid = envelope.data?.mid, mid != Int(cookies.dedeUserID) {
                throw PassportError.invalidResponse
            }
            if let fallbackCookies, cookies.dedeUserID != fallbackCookies.dedeUserID {
                throw PassportError.invalidResponse
            }
            return .confirmed(cookies, accessKey: envelope.data?.accessToken)
        case let code:
            throw PassportError.rejected("\(envelope.message ?? String(localized: "登录失败")) (code \(code))")
        }
    }

    // MARK: - 用 Cookie 换 App 凭据

    /// 网页登录（账号密码、网页扫码兜底）只有 Cookie，没有 `access_key`，App 推荐就只能按访客推。
    /// 用已登录的 Cookie 替自己确认一张iPhone App
    /// 登录二维码，再像扫码一样轮询出 `access_key`（PiliPlus 把这个确认接口标为「cookie转access_key」）。
    /// 旧链路仅保留用于原有回归；生产入口已改为 SMSPassport，不保证设备列表新增条目。
    static func exchangeAccessKey(cookies: LoginCookies) async throws -> String {
        let info = try await generateAppQRCode()
        let request = try makeAppConfirmationRequest(authCode: info.authCode, cookies: cookies)
        let (envelope, response) = try await sendEnvelope(request)
        guard (200...299).contains(response.statusCode) else { throw PassportError.invalidResponse }
        guard envelope.code == 0 else {
            throw PassportError.rejected("\(envelope.message ?? String(localized: "确认登录失败")) (code \(envelope.code))")
        }
        // 确认后服务端偶尔要一小会儿才把状态改成已确认。
        for attempt in 0..<4 {
            if attempt > 0 { try await Task.sleep(for: .milliseconds(500)) }
            if case .confirmed(_, let accessKey?) = try await pollAppQRCode(info.authCode, fallbackCookies: cookies), !accessKey.isEmpty {
                return accessKey
            }
        }
        throw PassportError.rejected(String(localized: "未能获取 App 登录凭据"))
    }

    /// 测试验证原样 Cookie/CSRF 与 passport 域名；不借共享 Cookie 罐补凭据。
    static func makeAppConfirmationRequest(authCode: String, cookies: LoginCookies) throws -> URLRequest {
        var request = try makeRequest(path: "x/passport-tv-login/h5/qrcode/confirm")
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("SESSDATA=\(cookies.sessdata); bili_jct=\(cookies.biliJct); DedeUserID=\(cookies.dedeUserID)",
                         forHTTPHeaderField: "Cookie")
        request.httpBody = formEncoded(["auth_code": authCode, "csrf": cookies.biliJct, "scanning_type": "3"])
            .data(using: .utf8)
        request.httpShouldHandleCookies = false
        return request
    }

    /// App 端接口统一走 POST + 签名后的表单体。
    private static func postSigned<Response: Decodable>(
        path: String,
        params: [String: String]
    ) async throws -> Response {
        guard let url = URL(string: baseURL.appendingPathComponent(path).absoluteString) else {
            throw PassportError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(BiliHeaders.appUserAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = AppSigner.queryString(from: params).data(using: .utf8)

        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw PassportError.invalidResponse
        }
        do {
            let envelope = try JSONDecoder().decode(TypedEnvelope<Response>.self, from: data)
            guard envelope.code == 0, let payload = envelope.data else {
                throw PassportError.rejected("\(envelope.message ?? String(localized: "登录服务异常")) (code \(envelope.code))")
            }
            return payload
        } catch let error as PassportError {
            throw error
        } catch {
            throw PassportError.invalidResponse
        }
    }

    // MARK: - 账号密码登录

    struct WebKey: Decodable, Sendable {
        /// 本次加密用的盐。
        let hash: String
        /// PEM 格式的 RSA 公钥。
        let key: String
    }

    static func webKey() async throws -> WebKey {
        try await get(path: "x/passport-login/web/key")
    }

    /// 极验（GT3）下发参数。`token` 要原样带回登录表单；gt/challenge 交给
    /// 滑块验证 WebView，验证成功后得到的 challenge/validate/seccode 一并回传。
    struct CaptchaInfo: Decodable, Sendable {
        let token: String
        let gt: String
        let challenge: String

        enum CodingKeys: String, CodingKey {
            case token
            case gt
            case challenge
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            token = try container.decode(String.self, forKey: .token)
            let geetest = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .gt)
            gt = try geetest.decode(String.self, forKey: .gt)
            challenge = try geetest.decode(String.self, forKey: .challenge)
        }
    }

    static func captcha() async throws -> CaptchaInfo {
        try await get(path: "x/passport-login/captcha", query: ["source": "main_web"])
    }

    /// 提交账号密码。`passwordEncrypted` 是 `PasswordCipher` 加密后的结果；
    /// 极验四件套来自 `captcha()` + 滑块验证的回调。
    static func passwordLogin(
        username: String,
        passwordEncrypted: String,
        captchaToken: String,
        challenge: String,
        validate: String,
        seccode: String
    ) async throws -> LoginCookies {
        var request = try makeRequest(path: "x/passport-login/web/login")
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form: [String: String] = [
            "username": username,
            "password": passwordEncrypted,
            "keep": "true",
            "token": captchaToken,
            "challenge": challenge,
            "validate": validate,
            "seccode": seccode
        ]
        request.httpBody = Self.formEncoded(form).data(using: .utf8)

        let (envelope, response) = try await sendEnvelope(request)
        guard (200...299).contains(response.statusCode) else {
            throw PassportError.invalidResponse
        }
        guard envelope.code == 0 else {
            throw PassportError.rejected("\(envelope.message ?? String(localized: "登录失败")) (code \(envelope.code))")
        }
        guard let cookies = loginCookies(from: response) else {
            throw PassportError.missingCookies
        }
        return cookies
    }

    // MARK: - 传输

    private static func makeRequest(path: String, query: [String: String] = [:]) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw PassportError.invalidResponse
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            throw PassportError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(BiliHeaders.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(BiliHeaders.referer, forHTTPHeaderField: "Referer")
        return request
    }

    /// 登录相关请求的统一出口：不让系统的共享 Cookie 罐插手，并且对
    /// 「连接被中断」这类抖动补发一次。
    ///
    /// iOS 复用 HTTP/2 长连接时，服务端如果已经悄悄关掉了连接，正在发的请求
    /// 会以 `-1005 networkConnectionLost`（就是那句 connection lost）失败。
    /// GET 系统会自己重发，POST 不会——它不是幂等操作。而扫码那条 App 链路
    /// 从生成到轮询全是 POST，于是一次抖动就把整个登录流程判了死刑。
    ///
    /// 关闭自动 Cookie 还有一层用意：登录态由我们自己保管（Keychain + 手写
    /// Cookie 头），共享罐里若留着上一次登录的 SESSDATA，会被系统自动贴到
    /// 登录请求上，让服务端看到一个自相矛盾的会话。
    private static func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var request = request
        request.httpShouldHandleCookies = false
        do {
            return try await AppNetwork.session.data(for: request)
        } catch let error as URLError where isTransient(error) {
            try await Task.sleep(for: .milliseconds(400))
            return try await AppNetwork.session.data(for: request)
        }
    }

    /// 这次失败是不是网络抖动（重发一次就可能成功），而不是服务端的业务拒绝。
    static func isTransient(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        switch error.code {
        case .networkConnectionLost, .timedOut, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    /// 登录失败时给用户看的一句话。URLError 的系统文案是英文的（「The network
    /// connection was lost.」），对用户既看不懂也没有下一步动作。
    static func failureText(for error: Error) -> String {
        guard let urlError = error as? URLError else { return error.localizedDescription }
        if isTransient(urlError) {
            return String(localized: "网络连接不稳定，请稍后再试（\(urlError.code.rawValue)）")
        }
        return String(localized: "网络请求失败（\(urlError.code.rawValue)）")
    }

    /// 只关心 envelope 的请求（扫码轮询、密码登录）走这里，响应头要单独保留。
    private static func sendEnvelope(_ request: URLRequest) async throws -> (Envelope, HTTPURLResponse) {
        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else {
            throw PassportError.invalidResponse
        }
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            return (envelope, http)
        } catch {
            throw PassportError.invalidResponse
        }
    }

    private struct Envelope: Decodable {
        let code: Int
        let message: String?
        let data: DataPlaceholder?

        struct DataPlaceholder: Decodable {}
    }

    private struct TypedEnvelope<Payload: Decodable>: Decodable {
        let code: Int
        let message: String?
        let data: Payload?
    }

    /// 常规 GET：解出强类型的 data 字段。
    private static func get<Response: Decodable>(path: String, query: [String: String] = [:]) async throws -> Response {
        let request = try makeRequest(path: path, query: query)
        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw PassportError.invalidResponse
        }

        do {
            let envelope = try JSONDecoder().decode(TypedEnvelope<Response>.self, from: data)
            guard envelope.code == 0, let payload = envelope.data else {
                throw PassportError.rejected("\(envelope.message ?? String(localized: "登录服务异常")) (code \(envelope.code))")
            }
            return payload
        } catch let error as PassportError {
            throw error
        } catch {
            throw PassportError.invalidResponse
        }
    }

    private static func formEncoded(_ form: [String: String]) -> String {
        var components = URLComponents()
        components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.percentEncodedQuery ?? ""
    }

    /// 从 Set-Cookie 头里取 SESSDATA / bili_jct / DedeUserID。
    private static func loginCookies(from response: HTTPURLResponse) -> LoginCookies? {
        let headerFields = Dictionary(
            uniqueKeysWithValues: response.allHeaderFields.compactMap { key, value -> (String, String)? in
                guard let name = key as? String, let text = value as? String else { return nil }
                return (name, text)
            }
        )
        let cookies = HTTPCookie.cookies(
            withResponseHeaderFields: headerFields,
            for: response.url ?? baseURL
        )
        var values: [String: String] = [:]
        for cookie in cookies {
            values[cookie.name] = cookie.value
        }
        guard let sessdata = values["SESSDATA"],
              let biliJct = values["bili_jct"],
              let dedeUserID = values["DedeUserID"]
        else { return nil }
        return LoginCookies(sessdata: sessdata, biliJct: biliJct, dedeUserID: dedeUserID)
    }
}
