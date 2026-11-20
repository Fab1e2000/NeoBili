import Foundation

public enum BiliHeaders {
    public static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    public static let referer = "https://www.bilibili.com"

    /// App UA 由 AppClientIdentity 生成，与请求参数及 app-key 头共用协议身份。
    static let appUserAgent = AppClientIdentity.userAgent

    /// PiliPlus 账号拦截器给 App 请求补的头；登录后再带上 mid 和由它算出的 aurora eid。
    static func appAccountHeaders(mid: Int?) -> [String: String] {
        var headers = ["env": "prod", "app-key": AppClientIdentity.mobiApp, "x-bili-aurora-zone": "sh001"]
        if let mid, mid > 0 {
            headers["x-bili-mid"] = String(mid)
            headers["x-bili-aurora-eid"] = auroraEID(mid: mid)
        }
        return headers
    }

    /// 与 PiliPlus IdUtils.genAuroraEid 相同：mid 的十进制字节逐位异或固定密钥，再做无填充 base64。
    static func auroraEID(mid: Int) -> String {
        let key = Array("ad1va46a7lza".utf8)
        let bytes = Array(String(mid).utf8).enumerated().map { $0.element ^ key[$0.offset % key.count] }
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "=", with: "")
    }
}
