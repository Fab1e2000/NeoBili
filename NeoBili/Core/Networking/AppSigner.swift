import CryptoKit
import Foundation

/// 与现有扫码登录签名配套的客户端身份，推荐和反馈共用，避免各接口自行拼接。
enum AppClientIdentity {
    static let mobiApp = "android_hd"
    static let build = "2001100"
    static let userAgent = "Mozilla/5.0 BiliDroid/2.0.1 (bbcallen@gmail.com) os/android model/android_hd mobi_app/android_hd build/2001100 channel/master innerVer/2001100 osVer/15 network/2"
    static let parameters = ["mobi_app": mobiApp, "build": build, "platform": "android",
                             "device": "pad", "channel": "master"]
}

/// B 站 APP 端接口（app.bilibili.com、passport-tv-login）的参数签名。
///
/// 网页端接口靠 Cookie 认证、靠 WBI 签名（见 `WBISigner`）；APP 端是另一套：
/// 认证靠 `access_key`，签名靠 appkey/appsec。两者互不通用，所以这里单独一份。
///
/// 算法本身很简单：补上 `appkey` 和秒级 `ts` → 按参数名排序拼成 query 串 →
/// 末尾接上 appsec → 取 MD5 作为 `sign`。服务端用同样的步骤复算，对不上就返回
/// 「API 校验密匙错误」。
enum AppSigner {
    /// android_hd（HD 版）的签名配置；扫码登录、推荐和反馈使用同一套身份。
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
