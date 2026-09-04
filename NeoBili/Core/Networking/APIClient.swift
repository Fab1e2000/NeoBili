import Foundation

enum BiliAPIError: Error, LocalizedError {
    case invalidURL
    case missingWbiKeys
    case httpStatus(Int)
    case apiError(code: Int, message: String)
    case decoding(Error)
    case riskControlled
    case missingAccessKey

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的请求地址"
        case .missingWbiKeys: return "无法获取 WBI 签名密钥"
        case .httpStatus(let code): return "网络请求失败 (HTTP \(code))"
        case .apiError(let code, let message): return "\(message) (code \(code))"
#if DEBUG
        // 开发版把出错的字段路径带出来。只写「数据解析失败」时，
        // 排查只能靠猜是哪个接口的哪个字段变了。
        case .decoding(let error): return "数据解析失败：\(Self.diagnostic(for: error))"
#else
        case .decoding: return "数据解析失败"
#endif
        case .riskControlled: return "请求被 B 站风控拦截，请稍后重试"
        case .missingAccessKey: return "该操作需要 App 端登录凭据，请退出后用扫码方式重新登录"
        }
    }

#if DEBUG
    /// DecodingError 里真正有用的是「哪个字段、缺了还是类型不对」。
    private static func diagnostic(for error: Error) -> String {
        guard let error = error as? DecodingError else { return error.localizedDescription }

        func path(_ context: DecodingError.Context) -> String {
            let keys = context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }
            return keys.isEmpty ? "(根)" : keys.joined(separator: ".")
        }

        switch error {
        case .keyNotFound(let key, let context):
            return "缺字段 \(path(context)).\(key.stringValue)"
        case .typeMismatch(let type, let context):
            return "\(path(context)) 不是 \(type)"
        case .valueNotFound(let type, let context):
            return "\(path(context)) 是 null（需要 \(type)）"
        case .dataCorrupted(let context):
            return "\(path(context)) 内容异常"
        @unknown default:
            return error.localizedDescription
        }
    }
#endif
}

/// Envelope every Bilibili web-API JSON response is wrapped in.
struct BiliResponse<T: Decodable>: Decodable {
    let code: Int
    let message: String
    let data: T?
}

/// Thin async wrapper around URLSession for talking to Bilibili's public web
/// endpoints as an anonymous (logged-out) client.
struct APIClient {
    static let shared = APIClient()

    private static let baseURL = URL(string: "https://api.bilibili.com")!
    private static let appBaseURL = URL(string: "https://app.bilibili.com")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Performs a GET request against `path` with `params`, optionally WBI-signing
    /// the query first, and decodes the `data` field of the response envelope.
    func get<T: Decodable>(
        path: String,
        params: [String: String] = [:],
        requiresWBI: Bool = false,
        additionalHeaders: [String: String] = [:]
    ) async throws -> T {
        var finalParams = params
        if requiresWBI {
            finalParams = try await WBISigner.shared.sign(params: params)
        }

        guard var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw BiliAPIError.invalidURL
        }
        // 自己转义，不交给 URLComponents。
        //
        // URLComponents 生成查询串时会把 `+ , : / @` 这些字符原样留下，而 WBI
        // 摘要是按 `encodeURIComponent` 的规则算的（全部转义）。两边一旦不一致，
        // 服务端重算出来的签名就对不上：随机指纹里只要出现一个 `+`，UP 主投稿
        // 列表这种严格接口就回 -403。用同一套字符集编码，字节层面保持一致。
        components.percentEncodedQueryItems = finalParams
            .sorted { $0.key < $1.key }
            .map { key, value in
                URLQueryItem(
                    name: key,
                    value: value.addingPercentEncoding(withAllowedCharacters: .wbiQueryValueAllowed) ?? value
                )
            }

        guard let url = components.url else {
            throw BiliAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        await applyCommonHeaders(to: &request)
        // 搜索等接口会校验自己的网页来源。调用方最后覆盖默认值，既让普通
        // API 继续共用全站 Referer，也不必为了一个特殊接口复制整段传输代码。
        for (name, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return try await perform(request)
    }

    /// 少数接口不在 api.bilibili.com 上，返回体也没有 `{code, message, data}`
    /// 这层信封——搜索联想就是这样：结果直接挂在 `result` 上，而且没有候选词
    /// 时连 `code` 都不是 0。这里只负责带上公共请求头并把整个响应体解出来，
    /// 具体形状由调用方自己定义。
    func getRaw<T: Decodable>(
        url: URL,
        additionalHeaders: [String: String] = [:]
    ) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        await applyCommonHeaders(to: &request)
        for (name, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw BiliAPIError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw BiliAPIError.decoding(error)
        }
    }

    /// Performs a POST with a form-encoded body. Used by the logged-in write
    /// operations (取消收藏、删除历史、移出稍后再看)： response data carries
    /// nothing useful beyond the envelope's `code`/`message`, so it is decoded
    /// into an empty placeholder and only the business code is checked.
    func post(
        path: String,
        form: [String: String] = [:],
        additionalHeaders: [String: String] = [:]
    ) async throws {
        let _: BiliEmptyData = try await post(path: path, form: form, additionalHeaders: additionalHeaders)
    }

    /// 同上，但把响应的 `data` 解出来。点赞这类接口会在 data 里回一段提示文案。
    func post<T: Decodable>(
        path: String,
        form: [String: String] = [:],
        additionalHeaders: [String: String] = [:]
    ) async throws -> T {
        try await postJSONBody(
            path: path,
            query: form,
            jsonBody: nil,
            additionalHeaders: additionalHeaders
        )
    }

    /// 部分网页端接口已迁移为 JSON body（如动态点赞 `dyn/thumb`，
    /// 表单编码会被判成参数错误 4100001）。PiliPlus 用的就是这个格式：
    /// csrf 走 query，业务参数走 JSON body。
    func postJSON(
        path: String,
        query: [String: String] = [:],
        json: [String: Any],
        additionalHeaders: [String: String] = [:]
    ) async throws {
        let _: BiliEmptyData = try await postJSONBody(
            path: path,
            query: query,
            jsonBody: json,
            additionalHeaders: additionalHeaders
        )
    }

    private func postJSONBody<T: Decodable>(
        path: String,
        query: [String: String],
        jsonBody: [String: Any]?,
        additionalHeaders: [String: String]
    ) async throws -> T {
        guard var components = URLComponents(
            string: Self.baseURL.appendingPathComponent(path).absoluteString
        ) else {
            throw BiliAPIError.invalidURL
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            throw BiliAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.httpMethod = "POST"
        await applyCommonHeaders(to: &request)
        // 关注等接口会校验自己的来源站点，调用方最后覆盖默认的全站 Referer。
        for (name, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }

        if let jsonBody,
           JSONSerialization.isValidJSONObject(jsonBody),
           let data = try? JSONSerialization.data(withJSONObject: jsonBody) {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = data
        } else {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var formComponents = URLComponents()
            formComponents.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            request.httpBody = formComponents.percentEncodedQuery?.data(using: .utf8)
        }

        return try await perform(request)
    }

    /// APP 端接口（app.bilibili.com）。
    ///
    /// 和网页端是完全两套认证：这里不发 Cookie，改用 `access_key` 表明身份，
    /// 再用 appkey/appsec 给整组参数签名（见 `AppSigner`）。UA 也必须换成
    /// BiliDroid 那串，否则请求会被当成非法客户端。
    ///
    /// 目前只有「点踩」需要走这条路——网页端没有对应的写接口。
    func postApp(
        path: String,
        form: [String: String] = [:]
    ) async throws {
        guard let accessKey = await DeviceIdentity.shared.accessKey, !accessKey.isEmpty else {
            throw BiliAPIError.missingAccessKey
        }
        guard let url = URL(string: Self.appBaseURL.appendingPathComponent(path).absoluteString) else {
            throw BiliAPIError.invalidURL
        }

        var params = form
        params["access_key"] = accessKey
        let signed = AppSigner.signed(params)

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(BiliHeaders.appUserAgent, forHTTPHeaderField: "User-Agent")
        // 签名串和请求体必须逐字节一致，所以两边共用同一个拼接函数。
        request.httpBody = AppSigner.queryString(from: signed).data(using: .utf8)

        let _: BiliEmptyData = try await perform(request)
    }

    /// Cookie（含登录态）与 UA/Referer 是每个请求的公共部分，集中在这里拼。
    ///
    /// 同时关掉系统的自动 Cookie：登录态由 App 自己保管（Keychain + 下面这个
    /// 手写的 Cookie 头）。如果放任 `HTTPCookieStorage` 也往请求上贴，退出登录
    /// 之后共享罐里残留的 SESSDATA 会继续被发出去——界面显示已退出，接口那边
    /// 却还是登录态，重新登录时两份凭据还会互相打架。
    private func applyCommonHeaders(to request: inout URLRequest) async {
        request.httpShouldHandleCookies = false
        request.setValue(BiliHeaders.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(BiliHeaders.referer, forHTTPHeaderField: "Referer")
        let cookie = await DeviceIdentity.shared.cookieHeader()
        if !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw BiliAPIError.httpStatus(status)
        }

        do {
            let decoded = try JSONDecoder().decode(BiliResponse<T>.self, from: data)
            guard decoded.code == 0 else {
                throw BiliAPIError.apiError(code: decoded.code, message: decoded.message)
            }
            guard let payload = decoded.data else {
                // 关注、点踩这类写接口成功时根本不返回 data。调用方要的是
                // `BiliEmptyData` 之类的占位类型时，用空对象把它补出来即可；
                // 真正需要内容的类型仍会解码失败，落到下面的错误分支。
                if let placeholder = try? JSONDecoder().decode(T.self, from: Data("{}".utf8)) {
                    return placeholder
                }
                throw BiliAPIError.apiError(code: decoded.code, message: "响应缺少 data 字段")
            }
            return payload
        } catch let error as BiliAPIError {
            throw error
        } catch {
            throw BiliAPIError.decoding(error)
        }
    }
}

/// POST 写操作响应的 data 基本没有内容（`{}`）；占位类型让解码忽略全部字段。
struct BiliEmptyData: Decodable {}
