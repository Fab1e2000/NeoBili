#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation

/// 保留的扫码和密码登录协议适配器，供旧流程与回归使用；当前界面入口为 SMSPassport。
/// 网页登录从 Set-Cookie 读取凭据，App 扫码从 JSON 读取 token 与 Cookie。
enum BiliPassport {
    typealias LoginCookies = LoginModels.LoginCookies

    typealias PassportError = LoginModels.PassportError

    private static let baseURL = URL(string: "https://passport.bilibili.com")!

    // MARK: - 扫码登录

    typealias QRCodeInfo = LoginModels.QRCodeInfo

    static func generateQRCode(session: URLSession) async throws -> QRCodeInfo {
        try await get(path: "x/passport-login/web/qrcode/generate", session: session)
    }

    typealias QRCodePollOutcome = LoginModels.QRCodePollOutcome

    /// 轮询扫码结果。注意业务状态码在 `data.code` 里（顶层 `code` 恒为 0，
    /// 直接读顶层会把「未扫码」误判成「登录成功」）：
    /// 86101 未扫码、86090 已扫码未确认、86038 已过期、0 已确认（此刻
    /// Set-Cookie 才会带上 SESSDATA 等凭据）。
    static func pollQRCode(_ qrcodeKey: String, session: URLSession) async throws -> QRCodePollOutcome {
        let request = try makeRequest(path: "x/passport-login/web/qrcode/poll", query: ["qrcode_key": qrcodeKey])
        let (data, response) = try await send(request, session: session)
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

    /// 旧 App 扫码链路返回 access_token 与 Cookie，当前登录界面使用短信验证码。
    typealias AppQRCodeInfo = LoginModels.AppQRCodeInfo

    static func generateAppQRCode(session: URLSession) async throws -> AppQRCodeInfo {
        let params = AppSigner.signed(
            AppClientIdentity.parameters.merging(["local_id": "0"]) { _, value in value },
            purpose: .passport
        )
        return try await postSigned(path: "x/passport-tv-login/qrcode/auth_code", params: params, session: session)
    }

    /// 轮询 App 扫码结果。
    ///
    /// 和网页那条链路不同，这里的业务状态码在**顶层** `code` 上，凭据也在
    /// JSON body 里而不是 Set-Cookie 头里：
    /// 86039 未确认、86038 已过期、0 已确认。
    static func pollAppQRCode(_ authCode: String, fallbackCookies: LoginCookies? = nil, session: URLSession) async throws -> QRCodePollOutcome {
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

        let (data, response) = try await send(request, session: session)
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

    /// 旧 Cookie 换 App 凭据链路：确认二维码后轮询 token。生产补授权通过 SMSPassport 完成。
    static func exchangeAccessKey(cookies: LoginCookies, session: URLSession) async throws -> String {
        let info = try await generateAppQRCode(session: session)
        let request = try makeAppConfirmationRequest(authCode: info.authCode, cookies: cookies)
        let (envelope, response) = try await sendEnvelope(request, session: session)
        guard (200...299).contains(response.statusCode) else { throw PassportError.invalidResponse }
        guard envelope.code == 0 else {
            throw PassportError.rejected("\(envelope.message ?? String(localized: "确认登录失败")) (code \(envelope.code))")
        }
        // 确认后服务端偶尔要一小会儿才把状态改成已确认。
        for attempt in 0..<4 {
            if attempt > 0 { try await Task.sleep(for: .milliseconds(500)) }
            if case .confirmed(_, let accessKey?) = try await pollAppQRCode(info.authCode, fallbackCookies: cookies, session: session), !accessKey.isEmpty {
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
        params: [String: String],
        session: URLSession
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

        let (data, response) = try await send(request, session: session)
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

    typealias WebKey = LoginModels.WebKey

    static func webKey(session: URLSession) async throws -> WebKey {
        try await get(path: "x/passport-login/web/key", session: session)
    }

    /// 极验（GT3）下发参数。`token` 要原样带回登录表单；gt/challenge 交给
    /// 滑块验证 WebView，验证成功后得到的 challenge/validate/seccode 一并回传。
    typealias CaptchaInfo = LoginModels.CaptchaInfo

    static func captcha(session: URLSession) async throws -> CaptchaInfo {
        try await get(path: "x/passport-login/captcha", query: ["source": "main_web"], session: session)
    }

    /// 提交账号密码。`passwordEncrypted` 是 `PasswordCipher` 加密后的结果；
    /// 极验四件套来自 `captcha()` + 滑块验证的回调。
    static func passwordLogin(
        username: String,
        passwordEncrypted: String,
        captchaToken: String,
        challenge: String,
        validate: String,
        seccode: String,
        session: URLSession
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

        let (envelope, response) = try await sendEnvelope(request, session: session)
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

    /// 旧登录请求的传输出口，禁用共享 Cookie 罐，并按本适配器策略重试一次连接错误。
    /// SMSPassport 使用独立传输，短信写请求不自动重试。
    private static func send(_ request: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
        var request = request
        request.httpShouldHandleCookies = false
        do {
            return try await session.data(for: request)
        } catch let error as URLError where isTransient(error) {
            try await Task.sleep(for: .milliseconds(400))
            return try await session.data(for: request)
        }
    }

    /// 这次失败是不是网络抖动（重发一次就可能成功），而不是服务端的业务拒绝。
    static func isTransient(_ error: Error) -> Bool { LoginModels.isTransient(error) }

    /// 登录失败时给用户看的一句话。URLError 的系统文案是英文的（「The network
    /// connection was lost.」），对用户既看不懂也没有下一步动作。
    static func failureText(for error: Error) -> String { LoginModels.failureText(for: error) }

    /// 只关心 envelope 的请求（扫码轮询、密码登录）走这里，响应头要单独保留。
    private static func sendEnvelope(_ request: URLRequest, session: URLSession) async throws -> (Envelope, HTTPURLResponse) {
        let (data, response) = try await send(request, session: session)
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
    private static func get<Response: Decodable>(path: String, query: [String: String] = [:], session: URLSession) async throws -> Response {
        let request = try makeRequest(path: path, query: query)
        let (data, response) = try await send(request, session: session)
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
