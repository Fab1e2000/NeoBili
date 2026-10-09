import Foundation

/// Credentials are captured by APIClient after checking the caller's login session.
/// Encoders have no access to Keychain, DeviceIdentity or a network connection.
struct AppAccountSnapshot: Sendable {
    let accessKey: String?
    let mid: Int?
    let sessionID: UUID
}

struct AppRequestContext: Sendable {
    let account: AppAccountSnapshot
    var headers: [String: String] = [:]
}

/// Only currently implemented wire formats. New verified protocols belong here,
/// while APIClient retains authentication, response handling and retry decisions.
enum AppRequest: Sendable {
    case get(path: String, parameters: [String: String], requiresAccountCredential: Bool, usesAPIHost: Bool = false)
    case form(path: String, parameters: [String: String], usesAPIHost: Bool)
    case grpc(path: String, payload: Data)
    case unrealtimeLog(body: Data, eventCount: Int)
    case realtimeLog(body: Data, eventCount: Int)

    func validate(account: AppAccountSnapshot) throws {
        let hasKey = account.accessKey?.isEmpty == false
        switch self {
        case .form:
            guard hasKey else { throw BiliAPIError.missingAccessKey }
        case let .get(_, _, requiresAccountCredential, _):
            if requiresAccountCredential, account.mid != nil, !hasKey { throw BiliAPIError.missingAccessKey }
        case .grpc:
            if account.mid != nil, !hasKey { throw BiliAPIError.missingAccessKey }
        case .unrealtimeLog, .realtimeLog: break
        }
    }
}

protocol AppRequestEncoding: Sendable {
    func encode(_ operation: AppRequest, context: AppRequestContext) throws -> URLRequest
}

struct AppRequestEncoder: AppRequestEncoding {
    private let timestamp: @Sendable () -> Int

    init(timestamp: @escaping @Sendable () -> Int = { Int(Date().timeIntervalSince1970) }) {
        self.timestamp = timestamp
    }

    func encode(_ operation: AppRequest, context: AppRequestContext) throws -> URLRequest {
        let account = context.account
        try operation.validate(account: account)
        let key = account.accessKey.flatMap { $0.isEmpty ? nil : $0 }
        switch operation {
        case let .get(path, parameters, requiresAccountCredential, usesAPIHost):
            if requiresAccountCredential, account.mid != nil, key == nil { throw BiliAPIError.missingAccessKey }
            var query = parameters
            if let key { query["access_key"] = key }
            guard var components = URLComponents(url: (usesAPIHost ? Self.apiURL : Self.appURL).appendingPathComponent(path),
                                                 resolvingAgainstBaseURL: false) else { throw BiliAPIError.invalidURL }
            components.percentEncodedQuery = AppSigner.queryString(from: AppSigner.signed(query, timestamp: timestamp()))
            guard let url = components.url else { throw BiliAPIError.invalidURL }
            var request = common(url: url, context: context, timeout: 15)
            request.setValue(BiliHeaders.referer, forHTTPHeaderField: "Referer")
            // Endpoint headers have always overridden the defaults, including Referer.
            apply(context.headers, to: &request)
            return request
        case let .form(path, parameters, usesAPIHost):
            guard let key else { throw BiliAPIError.missingAccessKey }
            var fields = parameters
            fields["access_key"] = key
            var request = common(url: (usesAPIHost ? Self.apiURL : Self.appURL).appendingPathComponent(path),
                                 context: context, timeout: 10)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            apply(context.headers, to: &request)
            request.httpBody = AppSigner.queryString(from: AppSigner.signed(fields, timestamp: timestamp())).data(using: .utf8)
            return request
        case let .grpc(path, payload):
            if account.mid != nil, key == nil { throw BiliAPIError.missingAccessKey }
            guard let url = URL(string: "https://grpc.biliapi.net/" + path) else { throw BiliAPIError.invalidURL }
            var request = common(url: url, context: context, timeout: 15)
            request.httpMethod = "POST"
            request.httpBody = AppProto.frame(payload)
            request.setValue("application/grpc", forHTTPHeaderField: "Content-Type")
            request.setValue("trailers", forHTTPHeaderField: "te")
            request.setValue("15S", forHTTPHeaderField: "grpc-timeout")
            request.setValue("gzip", forHTTPHeaderField: "grpc-accept-encoding")
            apply(context.headers, to: &request)
            if let key { request.setValue("identify_v1 " + key, forHTTPHeaderField: "authorization") }
            let metadata = AppProto.string(1, account.accessKey) + AppProto.string(2, AppClientIdentity.mobiApp)
                + AppProto.string(3, "phone") + AppProto.integer(4, Int(AppClientIdentity.build) ?? 0)
                + AppProto.string(5, "pink_overseas") + AppProto.string(6, context.headers["buvid"])
                + AppProto.string(7, "ios")
            request.setValue(metadata.base64EncodedString(), forHTTPHeaderField: "x-bili-metadata-bin")
            return request
        case .unrealtimeLog, .realtimeLog:
            let body: Data
            let channel: String
            let eventCount: Int
            switch operation {
            case .unrealtimeLog(let value, let count): body = value; eventCount = count; channel = "unrealtime"
            case .realtimeLog(let value, let count): body = value; eventCount = count; channel = "realtime"
            default: preconditionFailure()
            }
            var request = common(url: URL(string: "https://dataflow.biliapi.com/log/pbmobile/\(channel)?ios")!,
                                 context: context, timeout: 10)
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
            // Account headers retain the existing app-key identity for this endpoint.
            apply(context.headers, to: &request)
            request.setValue(String(eventCount), forHTTPHeaderField: "Neuron-Events")
            return request
        }
    }

    private static let apiURL = URL(string: "https://api.bilibili.com")!
    private static let appURL = URL(string: "https://app.bilibili.com")!

    private func common(url: URL, context: AppRequestContext, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.httpShouldHandleCookies = false
        request.setValue(BiliHeaders.appUserAgent, forHTTPHeaderField: "User-Agent")
        apply(BiliHeaders.appAccountHeaders(mid: context.account.mid), to: &request)
        return request
    }

    private func apply(_ headers: [String: String], to request: inout URLRequest) {
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
    }
}
