import Foundation

enum LoginModels {
    struct LoginCookies: Codable, Equatable, Sendable {
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

    struct QRCodeInfo: Decodable, Sendable {
        /// 二维码内容本身，渲染成二维码图片给 B 站 App 扫。
        let url: String
        let qrcodeKey: String

        enum CodingKeys: String, CodingKey {
            case url
            case qrcodeKey = "qrcode_key"
        }
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

    struct AppQRCodeInfo: Decodable, Sendable {
        let url: String
        let authCode: String

        enum CodingKeys: String, CodingKey {
            case url
            case authCode = "auth_code"
        }
    }

    struct WebKey: Decodable, Sendable {
        /// 本次加密用的盐。
        let hash: String
        /// PEM 格式的 RSA 公钥。
        let key: String
    }

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

    static func failureText(for error: Error) -> String {
        guard let urlError = error as? URLError else { return error.localizedDescription }
        if isTransient(urlError) {
            return String(localized: "网络连接不稳定，请稍后再试（\(urlError.code.rawValue)）")
        }
        return String(localized: "网络请求失败（\(urlError.code.rawValue)）")
    }
}
