import Foundation

enum BiliAPIError: Error, LocalizedError {
    case invalidURL
    case missingWbiKeys
    case httpStatus(Int)
    case apiError(code: Int, message: String)
    case decoding(Error)
    case riskControlled

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的请求地址"
        case .missingWbiKeys: return "无法获取 WBI 签名密钥"
        case .httpStatus(let code): return "网络请求失败 (HTTP \(code))"
        case .apiError(let code, let message): return "\(message) (code \(code))"
        case .decoding: return "数据解析失败"
        case .riskControlled: return "请求被 B 站风控拦截，请稍后重试"
        }
    }
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
        components.queryItems = finalParams
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }

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

    /// Performs a POST with a form-encoded body. Used by the logged-in write
    /// operations (取消收藏、删除历史、移出稍后再看)： response data carries
    /// nothing useful beyond the envelope's `code`/`message`, so it is decoded
    /// into an empty placeholder and only the business code is checked.
    func post(
        path: String,
        form: [String: String] = [:]
    ) async throws {
        guard let url = URL(string: Self.baseURL.appendingPathComponent(path).absoluteString) else {
            throw BiliAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        await applyCommonHeaders(to: &request)

        var components = URLComponents()
        components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let _: BiliEmptyData = try await perform(request)
    }

    /// Cookie（含登录态）与 UA/Referer 是每个请求的公共部分，集中在这里拼。
    private func applyCommonHeaders(to request: inout URLRequest) async {
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
