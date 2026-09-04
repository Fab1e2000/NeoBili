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
            case .invalidResponse: return "登录服务响应异常"
            case .missingCookies: return "登录成功但未收到凭据"
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
        case confirmed(LoginCookies)
    }

    /// 轮询扫码结果。注意业务状态码在 `data.code` 里（顶层 `code` 恒为 0，
    /// 直接读顶层会把「未扫码」误判成「登录成功」）：
    /// 86101 未扫码、86090 已扫码未确认、86038 已过期、0 已确认（此刻
    /// Set-Cookie 才会带上 SESSDATA 等凭据）。
    static func pollQRCode(_ qrcodeKey: String) async throws -> QRCodePollOutcome {
        var request = try makeRequest(path: "x/passport-login/web/qrcode/poll", query: ["qrcode_key": qrcodeKey])
        let (data, response) = try await URLSession.shared.data(for: request)
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
            return .confirmed(cookies)
        case let code:
            throw PassportError.rejected("\(envelope.data?.message ?? envelope.message ?? "登录失败") (code \(code))")
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

        let (envelope, response) = try await send(request)
        guard (200...299).contains(response.statusCode) else {
            throw PassportError.invalidResponse
        }
        guard envelope.code == 0 else {
            throw PassportError.rejected("\(envelope.message ?? "登录失败") (code \(envelope.code))")
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

    /// 只关心 envelope 的请求（扫码轮询、密码登录）走这里，响应头要单独保留。
    private static func send(_ request: URLRequest) async throws -> (Envelope, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
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
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw PassportError.invalidResponse
        }

        do {
            let envelope = try JSONDecoder().decode(TypedEnvelope<Response>.self, from: data)
            guard envelope.code == 0, let payload = envelope.data else {
                throw PassportError.rejected("\(envelope.message ?? "登录服务异常") (code \(envelope.code))")
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
