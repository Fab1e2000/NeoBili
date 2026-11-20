import Foundation

public enum LoginModels {
    public struct LoginCookies: Codable, Equatable, Sendable {
        public let sessdata: String
        public let biliJct: String
        public let dedeUserID: String

        public init(
            sessdata: String,
            biliJct: String,
            dedeUserID: String
        ) {
            self.sessdata = sessdata
            self.biliJct = biliJct
            self.dedeUserID = dedeUserID
        }
    }

    public enum PassportError: LocalizedError, Equatable {
        case invalidResponse
        case missingCookies
        /// 服务端业务错误（验证码无效等），带上接口原话。
        case rejected(String)

        public var errorDescription: String? {
            switch self {
            case .invalidResponse: return String(localized: "登录服务响应异常")
            case .missingCookies: return String(localized: "登录成功但未收到凭据")
            case .rejected(let message): return message
            }
        }
    }

    private static func isTransient(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        switch error.code {
        case .networkConnectionLost, .timedOut, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    public static func failureText(for error: Error) -> String {
        guard let urlError = error as? URLError else { return error.localizedDescription }
        if isTransient(urlError) {
            return String(localized: "网络连接不稳定，请稍后再试（\(urlError.code.rawValue)）")
        }
        return String(localized: "网络请求失败（\(urlError.code.rawValue)）")
    }
}
