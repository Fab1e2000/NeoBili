import CryptoKit
import Foundation

/// B 站 APP 端接口（app.bilibili.com、passport-tv-login）的参数签名。
///
/// 网页端接口靠 Cookie 认证、靠 WBI 签名（见 `WBISigner`）；APP 端是另一套：
/// 认证靠 `access_key`，签名靠 appkey/appsec。两者互不通用，所以这里单独一份。
///
/// 算法本身很简单：补上 `appkey` 和秒级 `ts` → 按参数名排序拼成 query 串 →
/// 末尾接上 appsec → 取 MD5 作为 `sign`。服务端用同样的步骤复算，对不上就返回
/// 「API 校验密匙错误」。
enum AppSigner {
    /// iOS 登录与业务使用同一组密钥，不能发送 Android/HD token。
    /// 公共协议资料：docs/login/login_action/QR.md；与官方抓包签名在内存中复算一致。
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
    /// 转义规则要和服务端一致：这里用的是 JavaScript `encodeURIComponent` 那一套
    /// 保留字符集（`A-Za-z0-9-_.!~*'()` 之外全部转义）。用 Foundation 默认的
    /// `.urlQueryAllowed` 会漏掉 `+`、`&` 等字符，签名就会对不上。
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
