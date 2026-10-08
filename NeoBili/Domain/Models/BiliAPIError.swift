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
        case .invalidURL: return String(localized: "无效的请求地址")
        case .missingWbiKeys: return String(localized: "无法获取 WBI 签名密钥")
        case .httpStatus(let code): return String(localized: "网络请求失败 (HTTP \(code))")
        case .apiError(let code, let message): return "\(message) (code \(code))"
#if DEBUG
        // 开发版把出错的字段路径带出来。只写「数据解析失败」时，
        // 排查只能靠猜是哪个接口的哪个字段变了。
        case .decoding(let error): return String(localized: "数据解析失败：\(Self.diagnostic(for: error))")
#else
        case .decoding: return String(localized: "数据解析失败")
#endif
        case .riskControlled: return String(localized: "请求被 B 站风控拦截，请稍后重试")
        case .missingAccessKey: return String(localized: "App 授权未完成，请到「设置 → 推荐流」使用验证码授权")
        }
    }

#if DEBUG
    /// DecodingError 里真正有用的是「哪个字段、缺了还是类型不对」。
    private static func diagnostic(for error: Error) -> String {
        guard let error = error as? DecodingError else { return error.localizedDescription }

        func path(_ context: DecodingError.Context) -> String {
            let keys = context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }
            return keys.isEmpty ? String(localized: "(根)") : keys.joined(separator: ".")
        }

        switch error {
        case .keyNotFound(let key, let context):
            return String(localized: "缺字段 \(path(context)).\(key.stringValue)")
        case .typeMismatch(let type, let context):
            return String(localized: "\(path(context)) 不是 \(type)")
        case .valueNotFound(let type, let context):
            return String(localized: "\(path(context)) 是 null（需要 \(type)）")
        case .dataCorrupted(let context):
            return String(localized: "\(path(context)) 内容异常")
        @unknown default:
            return error.localizedDescription
        }
    }
#endif
}

/// Envelope every Bilibili web-API JSON response is wrapped in.
