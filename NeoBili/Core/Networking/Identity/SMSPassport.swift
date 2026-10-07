import Foundation

/// App 短信登录。登录尝试使用自己的设备身份，写请求不自动重试。
enum SMSPassport {
    struct Context: Sendable {
        let accountSession: UUID
        let headers: [String: String]
        let buvid: String
        let deviceID: String
        let loginSession: String
    }
    struct Country: Decodable, Identifiable, Hashable, Sendable {
        let id: Int
        let cname: String
        let countryId: String
        enum CodingKeys: String, CodingKey { case id, cname; case countryId = "country_id" }
    }
    struct Captcha: Identifiable, Sendable {
        let token: String
        let gt: String
        let challenge: String
        var id: String { challenge }
    }
    struct ChallengeResult: Sendable {
        let challenge: String
        let validate: String
        let seccode: String
    }
    enum SendOutcome: Sendable { case sent(String); case captcha(Captcha) }
    struct Credentials: Codable, Equatable, Sendable {
        let cookies: BiliPassport.LoginCookies
        let accessKey: String
        var refreshToken: String? = nil
        var expiresIn: Int? = nil
    }
    enum LoginOutcome: Sendable { case confirmed(Credentials); case verification(URL) }
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    static let live: Transport = { try await AppNetwork.session.data(for: $0) }

    static func prepare(identity: DeviceIdentity = .shared) async throws -> Context {
        let accountSession = identity.loginSessionID
        let headers = try await identity.appRequestHeaders(expectedSessionID: accountSession)
        let buvid = await identity.appBuvid()
        let deviceID = await identity.registeredDeviceID() ?? ""
        try Task.checkCancellation()
        guard identity.loginSessionID == accountSession else { throw CancellationError() }
        return Context(accountSession: accountSession, headers: headers, buvid: buvid,
                       deviceID: deviceID, loginSession: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())
    }

    static func countries(transport: Transport = live) async throws -> [Country] {
        let request = URLRequest(url: URL(string: "https://passport.bilibili.com/web/generic/country/list")!)
        let json = try await object(request, transport: transport)
        try requireSuccess(json)
        guard let data = json["data"] as? [String: Any] else { throw BiliPassport.PassportError.invalidResponse }
        let raw = (data["common"] as? [[String: Any]] ?? []) + (data["others"] as? [[String: Any]] ?? [])
        let decoded = try JSONDecoder().decode([Country].self, from: JSONSerialization.data(withJSONObject: raw))
        var seen = Set<Int>()
        return decoded.filter { seen.insert($0.id).inserted }
    }

    static func baseParameters(_ context: Context) -> [String: String] {
        var parameters = AppClientIdentity.parameters.merging([
            "actionKey": "appkey", "statistics": AppClientIdentity.statistics,
            "c_locale": "zh-Hans_CN", "s_locale": "zh-Hans_CN", "disable_rcmd": "0",
            "buvid": context.buvid, "local_id": context.buvid,
            "device_name": "iPhone",
            "device_platform": AppClientIdentity.deviceName, "channel": "pink_overseas"
        ]) { _, new in new }
        if !context.deviceID.isEmpty { parameters["device_id"] = context.deviceID }
        if let guest = context.headers.first(where: { $0.key.lowercased() == "guestid" })?.value,
           let value = Int64(guest), AppGuestRegistration.isValid(value) {
            parameters["device_tourist_id"] = guest
        }
        return parameters
    }
    static func makeRequest(path: String, context: Context, fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://passport.bilibili.com/\(path)")!)
        request.httpMethod = "POST"
        applyHeaders(context, to: &request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let parameters = baseParameters(context).merging(fields) { _, new in new }
        request.httpBody = AppSigner.queryString(from: AppSigner.signed(parameters, purpose: .passport)).data(using: .utf8)
        return request
    }
    private static func applyHeaders(_ context: Context, to request: inout URLRequest) {
        request.timeoutInterval = 20
        request.httpShouldHandleCookies = false
        for (key, value) in context.headers { request.setValue(value, forHTTPHeaderField: key) }
        request.setValue(AppDeviceProtocol.traceID(), forHTTPHeaderField: "x-bili-trace-id")
        request.setValue(context.buvid, forHTTPHeaderField: "buvid")
        request.setValue(AppClientIdentity.userAgent, forHTTPHeaderField: "User-Agent")
    }
    /// 安全页继续使用当前登录的 App 身份，避免网页授权码与 App 兑换身份混用。
    static func securityRequest(url: URL, method: String, body: String, context: Context) throws -> [String: String] {
        let paths = ["/x/safecenter/user/info", "/x/safecenter/answer/questions", "/x/safecenter/answer/submit", "/x/safecenter/pwd/verify"]
        guard url.scheme == "https", url.host == "api.bilibili.com", url.user == nil, url.password == nil,
              paths.contains(url.path), ["GET", "POST"].contains(method), body.utf8.count <= 16_384,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw BiliPassport.PassportError.invalidResponse
        }
        func fields(_ encoded: String) throws -> [String: String] {
            var result: [String: String] = [:]
            for pair in encoded.split(separator: "&") {
                let pieces = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let key = String(pieces[0]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding,
                      let value = (pieces.count > 1 ? String(pieces[1]) : "").replacingOccurrences(of: "+", with: " ").removingPercentEncoding,
                      result[key] == nil else { throw BiliPassport.PassportError.invalidResponse }
                result[key] = value
            }
            return result
        }
        let identity = baseParameters(context)
        var query = try fields(components.percentEncodedQuery ?? "")
        query.merge(identity) { _, own in own }
        query.removeValue(forKey: "access_key")
        components.percentEncodedQuery = AppSigner.queryString(from: AppSigner.signed(query, purpose: .passport))
        var encodedBody = ""
        if method == "POST" {
            var data = try fields(body)
            data.merge(identity) { _, own in own }
            data.removeValue(forKey: "access_key")
            encodedBody = AppSigner.queryString(from: AppSigner.signed(data, purpose: .passport))
        }
        guard let destination = components.url else { throw BiliPassport.PassportError.invalidResponse }
        return ["url": destination.absoluteString, "body": encodedBody]
    }

    static func send(context: Context, phone: String, country: Int, captcha: Captcha? = nil,
                     result: ChallengeResult? = nil, transport: Transport = live) async throws -> SendOutcome {
        var fields = ["tel": phone, "cid": String(country), "login_session_id": context.loginSession,
                      "spm_id": "main.homepage.avatar-nologin.all.click", "otp_channel": "sms"]
        if let captcha, let result {
            fields.merge(["recaptcha_token": captcha.token, "gee_challenge": result.challenge,
                          "gee_validate": result.validate, "gee_seccode": result.seccode]) { _, new in new }
        }
        let request = makeRequest(path: "x/passport-login/sms/send", context: context, fields: fields)
        return try sendOutcome(try await object(request, transport: transport))
    }
    static func sendOutcome(_ json: [String: Any]) throws -> SendOutcome {
        let data = json["data"] as? [String: Any] ?? [:]
        if let raw = data["recaptcha_url"] as? String, !raw.isEmpty, let captcha = captcha(from: raw) {
            return .captcha(captcha)
        }
        try requireSuccess(json)
        guard let key = data["captcha_key"] as? String, !key.isEmpty else { throw BiliPassport.PassportError.invalidResponse }
        return .sent(key)
    }
    /// 支持服务端 recaptcha_url 的 params JSON / Base64 JSON，不猜验证码或 token。
    static func captcha(from raw: String) -> Captcha? {
        guard let url = URLComponents(string: raw) else { return nil }
        var values = Dictionary(url.queryItems?.map { ($0.name, $0.value ?? "") } ?? [], uniquingKeysWith: { _, new in new })
        if let params = values["params"] {
            let bytes = params.data(using: .utf8)
            let decoded = Data(base64Encoded: params)
            for data in [bytes, decoded].compactMap({ $0 }) {
                if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    for (key, value) in object { if let value = value as? String { values[key] = value } }
                    if let geetest = object["geetest"] as? [String: String] { values.merge(geetest) { _, new in new } }
                }
            }
        }
        guard let token = values["recaptcha_token"] ?? values["token"], !token.isEmpty,
              let gt = values["gt"] ?? values["gee_gt"], !gt.isEmpty,
              let challenge = values["challenge"] ?? values["gee_challenge"], !challenge.isEmpty else { return nil }
        return Captcha(token: token, gt: gt, challenge: challenge)
    }
    static func login(context: Context, phone: String, country: Int, code: String, key: String,
                      transport: Transport = live) async throws -> LoginOutcome {
        let fields = ["tel": phone, "cid": String(country), "code": code, "captcha_key": key,
                      "login_session_id": context.loginSession, "spm_id": "main.homepage.avatar-nologin.all.click"]
        return try loginOutcome(try await object(makeRequest(path: "x/passport-login/login/sms", context: context, fields: fields), transport: transport))
    }
    static func exchange(context: Context, code: String, transport: Transport = live) async throws -> LoginOutcome {
        let fields = ["code": code, "grant_type": "authorization_code"]
        return try loginOutcome(try await object(makeRequest(path: "x/passport-login/oauth2/access_token", context: context, fields: fields), transport: transport))
    }
    static func loginOutcome(_ json: [String: Any]) throws -> LoginOutcome {
        try requireSuccess(json)
        guard let data = json["data"] as? [String: Any] else { throw BiliPassport.PassportError.invalidResponse }
        if let status = data["status"] as? Int, status != 0 {
            guard let raw = data["url"] as? String, let url = URL(string: raw), isSecurityURL(url) else {
                throw BiliPassport.PassportError.rejected(String(localized: "登录需要额外验证，请重试"))
            }
            return .verification(url)
        }
        guard let token = data["token_info"] as? [String: Any], let key = token["access_token"] as? String, !key.isEmpty,
              let cookieInfo = data["cookie_info"] as? [String: Any], let cookies = cookieInfo["cookies"] as? [[String: Any]] else {
            throw BiliPassport.PassportError.missingCookies
        }
        var values: [String: String] = [:]
        for cookie in cookies { if let name = cookie["name"] as? String, let value = cookie["value"] as? String { values[name] = value } }
        guard let sessdata = values["SESSDATA"], !sessdata.isEmpty, let csrf = values["bili_jct"], !csrf.isEmpty,
              let mid = values["DedeUserID"], let number = Int(mid), number > 0,
              String(describing: token["mid"] ?? "") == mid else { throw BiliPassport.PassportError.invalidResponse }
        return .confirmed(Credentials(cookies: .init(sessdata: sessdata, biliJct: csrf, dedeUserID: mid), accessKey: key,
            refreshToken: (token["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            expiresIn: token["expires_in"] as? Int))
    }
    static func isSecurityURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "passport.bilibili.com" && url.path == "/h5/project-msg-auth/auth/entry"
    }
    private static func object(_ request: URLRequest, transport: Transport) async throws -> [String: Any] {
        var request = request
        request.httpShouldHandleCookies = false
        let (data, response) = try await transport(request)
        if !AppNetwork.isRegression, let http = response as? HTTPURLResponse {
            await DeviceIdentity.shared.observeAppResponse(http, request: request)
        }
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BiliPassport.PassportError.invalidResponse
        }
        try Task.checkCancellation()
        return json
    }
    private static func requireSuccess(_ json: [String: Any]) throws {
        guard let code = json["code"] as? Int else { throw BiliPassport.PassportError.invalidResponse }
        guard code == 0 else {
            throw BiliPassport.PassportError.rejected("\(json["message"] as? String ?? String(localized: "登录失败")) (\(code))")
        }
    }
}
