import CryptoKit
import Foundation

/// iPhone App 请求的参数签名，登录和业务共用同一组 iOS 密钥。
/// 补 appkey 与秒级 ts，排序并转义参数，末尾接 appsec 后计算 MD5 sign。
enum AppSigner {
    /// iOS 登录与业务使用同一组密钥，不能发送 Android/HD token。
    static let appKey = "27eb53fc9058f8c3"
    static let passportAppKey = appKey
    enum Purpose { case app, passport }

    /// 返回补齐了 `appkey`、`ts`、`sign` 的参数表。
    ///
    /// `timestamp` 只给测试注入固定值用；线上走默认的当前时间。
    static func signed(
        _ params: [String: String],
        purpose: Purpose = .app,
        timestamp: Int = Int(Date().timeIntervalSince1970),
        nativeEncoding: Bool = false
    ) -> [String: String] {
        var signedParams = params
        signedParams["appkey"] = purpose == .passport ? passportAppKey : appKey
        let appSecret = "c2ed53a74eeefe3cf99fbd01d8c9c375"
        signedParams["ts"] = String(timestamp)
        signedParams["sign"] = nil

        let query = queryString(from: signedParams, nativeEncoding: nativeEncoding)
        let digest = Insecure.MD5.hash(data: Data((query + appSecret).utf8))
        signedParams["sign"] = digest.map { String(format: "%02x", $0) }.joined()
        return signedParams
    }

    /// 参与签名的 query 串，也正好可以直接当请求体发出去。
    ///
    /// 默认保留 encodeURIComponent 字符集；nativeEncoding 供续期通道使用严格的 -_.~ 集合。
    /// 签名和传输必须选择相同模式，避免 +、& 等分隔符改变参数。
    static func queryString(from params: [String: String], nativeEncoding: Bool = false) -> String {
        params
            .sorted { $0.key < $1.key }
            .map { key, value in
                let encodedKey = percentEncoded(key, native: nativeEncoding)
                // 官方 iPhone 签名保留空值的等号；签名与传输共用同一份字节。
                return "\(encodedKey)=\(percentEncoded(value, native: nativeEncoding))"
            }
            .joined(separator: "&")
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"
    )

    private static func percentEncoded(_ value: String, native: Bool = false) -> String {
        value.addingPercentEncoding(withAllowedCharacters: native ? CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~") : unreserved) ?? value
    }
}
