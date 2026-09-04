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
    /// android_hd（HD 版）的密钥对。扫码登录返回的 access_key 与这一对绑定，
    /// 换成别的 appkey 去调 APP 接口会被判成无效凭据，所以两处必须用同一对。
    static let appKey = "dfca71928277209b"
    private static let appSecret = "b5475a8825547a4fc26c7d518eaaa02e"

    /// 返回补齐了 `appkey`、`ts`、`sign` 的参数表。
    ///
    /// `timestamp` 只给测试注入固定值用；线上走默认的当前时间。
    static func signed(
        _ params: [String: String],
        timestamp: Int = Int(Date().timeIntervalSince1970)
    ) -> [String: String] {
        var signedParams = params
        signedParams["appkey"] = appKey
        signedParams["ts"] = String(timestamp)
        signedParams["sign"] = nil

        let query = queryString(from: signedParams)
        let digest = Insecure.MD5.hash(data: Data((query + appSecret).utf8))
        signedParams["sign"] = digest.map { String(format: "%02x", $0) }.joined()
        return signedParams
    }

    /// 参与签名的 query 串，也正好可以直接当请求体发出去。
    ///
    /// 转义规则要和服务端一致：这里用的是 JavaScript `encodeURIComponent` 那一套
    /// 保留字符集（`A-Za-z0-9-_.!~*'()` 之外全部转义）。用 Foundation 默认的
    /// `.urlQueryAllowed` 会漏掉 `+`、`&` 等字符，签名就会对不上。
    static func queryString(from params: [String: String]) -> String {
        params
            .sorted { $0.key < $1.key }
            .map { key, value in
                let encodedKey = percentEncoded(key)
                // 空值只写键名，不写等号——这是服务端计算签名时的写法。
                return value.isEmpty ? encodedKey : "\(encodedKey)=\(percentEncoded(value))"
            }
            .joined(separator: "&")
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"
    )

    private static func percentEncoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }
}
