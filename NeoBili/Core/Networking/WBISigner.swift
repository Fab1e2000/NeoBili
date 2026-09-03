import Foundation
import CryptoKit

/// Implements Bilibili's "WBI" request signing scheme.
///
/// The web frontend derives a per-session "mixin key" from two key fragments
/// (`img_key` / `sub_key`) embedded in the URLs returned by the nav endpoint,
/// shuffles them through a fixed permutation table, and uses the result to
/// MD5-sign every query string (plus a `wts` timestamp) into a `w_rid` value.
/// Endpoints under `.../wbi/...` reject requests that don't carry a valid
/// `wts`/`w_rid` pair.
actor WBISigner {
    static let shared = WBISigner()

    private static let mixinKeyEncTab: [Int] = [
        46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
        27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
        37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
        22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52
    ]

    private let defaults = UserDefaults.standard
    private let mixinKeyDefaultsKey = "neobili.wbi.mixinKey"
    private let savedAtDefaultsKey = "neobili.wbi.mixinKeySavedAt"

    private var cachedMixinKey: String?
    private var cachedAt: Date?
    /// 同一时间只允许一个 nav 请求。多个接口同时启动时，其余的会复用这一个结果，
    /// 否则首屏会连着发好几次相同的密钥请求，把真正要用的接口挤到后面。
    private var refreshTask: Task<String, Error>?
    private init() {
        // 密钥写进本地存储，冷启动时不必再等一次 nav 请求。
        cachedMixinKey = defaults.string(forKey: mixinKeyDefaultsKey)
        let savedAt = defaults.double(forKey: savedAtDefaultsKey)
        cachedAt = savedAt > 0 ? Date(timeIntervalSince1970: savedAt) : nil
    }

    /// App 启动时先把密钥准备好，第一次视频请求就不用排在 nav 请求后面。
    nonisolated func warmUp() {
        Task { _ = try? await sign(params: [:]) }
    }

    /// Returns the query items with `wts` and `w_rid` appended, signed with the
    /// current mixin key.
    func sign(params: [String: String]) async throws -> [String: String] {
        let mixinKey = try await mixinKeyValue()
        var signedParams = params
        let wts = String(Int(Date().timeIntervalSince1970))
        signedParams["wts"] = wts

        let sortedKeys = signedParams.keys.sorted()
        let queryString = sortedKeys
            .map { key -> String in
                let value = sanitize(signedParams[key] ?? "")
                let encoded = value.addingPercentEncoding(withAllowedCharacters: .wbiQueryValueAllowed) ?? value
                return "\(key)=\(encoded)"
            }
            .joined(separator: "&")

        let digestInput = queryString + mixinKey
        let wRid = Insecure.MD5.hash(data: Data(digestInput.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        signedParams["w_rid"] = wRid
        return signedParams
    }

    /// Strips characters Bilibili's own signer filters out of values before hashing.
    private func sanitize(_ value: String) -> String {
        value.filter { !"!'()*".contains($0) }
    }

    private func mixinKeyValue() async throws -> String {
        if let cached = cachedMixinKey,
           let cachedAt,
           !cached.isEmpty,
           Self.isCacheFresh(savedAt: cachedAt) {
            return cached
        }
        if let refreshTask {
            return try await refreshTask.value
        }

        let task = Task { () throws -> String in
            let (imgKey, subKey) = try await fetchKeyFragments()
            let raw = imgKey + subKey
            let mixin = Self.mixinKeyEncTab
                .prefix(32)
                .map { raw[raw.index(raw.startIndex, offsetBy: $0)] }
            return String(mixin)
        }
        refreshTask = task
        defer { refreshTask = nil }

        let key = try await task.value
        let now = Date()
        cachedMixinKey = key
        cachedAt = now
        defaults.set(key, forKey: mixinKeyDefaultsKey)
        defaults.set(now.timeIntervalSince1970, forKey: savedAtDefaultsKey)
        return key
    }

    /// WBI 图片密钥并不需要按小时刷新。PiliPlus 也是把同一天拿到的密钥直接
    /// 持久复用；这样重新打开 App 后，首页推荐和第一个视频都能立刻签名，
    /// 不会因为上次启动已超过一小时而先串行等待一次 `/nav`。
    ///
    /// 单独保留成纯函数，既能固定“跨自然日才过期”的语义，也便于单元测试。
    static func isCacheFresh(
        savedAt: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        calendar.isDate(savedAt, inSameDayAs: now)
    }

    private struct NavResponse: Decodable {
        struct WbiImg: Decodable {
            let imgUrl: String
            let subUrl: String
            enum CodingKeys: String, CodingKey {
                case imgUrl = "img_url"
                case subUrl = "sub_url"
            }
        }
        struct DataPayload: Decodable {
            let wbiImg: WbiImg
            enum CodingKeys: String, CodingKey {
                case wbiImg = "wbi_img"
            }
        }
        let code: Int
        let data: DataPayload?
    }

    private func fetchKeyFragments() async throws -> (imgKey: String, subKey: String) {
        guard let url = URL(string: "https://api.bilibili.com/x/web-interface/nav") else {
            throw BiliAPIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(BiliHeaders.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(BiliHeaders.referer, forHTTPHeaderField: "Referer")
        let cookie = await DeviceIdentity.shared.cookieHeader()
        if !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        let decoded = try JSONDecoder().decode(NavResponse.self, from: data)
        guard let wbiImg = decoded.data?.wbiImg else {
            throw BiliAPIError.missingWbiKeys
        }
        let imgKey = filename(from: wbiImg.imgUrl)
        let subKey = filename(from: wbiImg.subUrl)
        guard !imgKey.isEmpty, !subKey.isEmpty else {
            throw BiliAPIError.missingWbiKeys
        }
        return (imgKey, subKey)
    }

    private func filename(from urlString: String) -> String {
        guard let url = URL(string: urlString) else { return "" }
        return url.deletingPathExtension().lastPathComponent
    }
}

private extension CharacterSet {
    /// RFC 3986 unreserved set plus the characters Bilibili's signer leaves
    /// unescaped; conservative enough for query values that already had
    /// `!'()*` filtered out.
    static let wbiQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+")
        return set
    }()
}
