import Foundation

extension BiliAPI {
    /// Requests a DASH-first play manifest for `bvid`/`cid`.
    ///
    /// mpv 能直接打开 DASH 拆开的视频、音频两条流（靠 `edl://` 伪协议拼成一个
    /// 输入，见 `PlaybackSourceBuilder.edlURL`），不需要像 AVFoundation 那样
    /// 先探测再拼 composition，所以 DASH 和 durl 对首帧速度没有区别——直接
    /// 按编码能力和画质优先选 DASH，durl 只在稿件不提供 DASH 时才用到。
    static func playURL(bvid: String, cid: Int, quality: Int = 127) async throws -> PlayURLData {
        let quality = String(max(1, quality))
        let formats: [[String: String]] = [
            ["qn": quality, "fnval": "4048", "fnver": "0", "fourk": "1", "otype": "json", "platform": "pc"],
            // 某些稿件的网页端参数不接受 4048，仍请求完整 DASH 能力集。
            ["qn": quality, "fnval": "16", "fnver": "0", "fourk": "1", "otype": "json", "platform": "pc"],
            // 最后的兼容路径：服务端已经合并好的文件。
            ["qn": "64", "fnval": "1", "fnver": "0", "otype": "json", "platform": "html5", "high_quality": "1"]
        ]

        for extraParams in formats {
            do {
                let payload = try await requestPlayURL(bvid: bvid, cid: cid, extraParams: extraParams)
                if payload.isRiskControlled {
                    throw BiliAPIError.riskControlled
                }
                if payload.hasPlayableStream {
                    return payload
                }
            } catch {
                // code -400 在这个接口中表示当前参数或流格式不适用。
                // 只有这种情况才换格式重试；断网、超时等错误仍立即显示。
                guard Self.isUnsupportedPlayFormat(error) else { throw error }
            }
        }

        throw BiliAPIError.apiError(code: -1, message: String(localized: "该视频暂不支持播放"))
    }

    private static func requestPlayURL(
        bvid: String,
        cid: Int,
        extraParams: [String: String]
    ) async throws -> PlayURLData {
        var params = extraParams
        params["bvid"] = bvid
        params["cid"] = String(cid)
        let isLoggedIn = await DeviceIdentity.shared.isLoggedIn
        params.merge(playbackContextParams(isLoggedIn: isLoggedIn)) { current, _ in current }
        return try await APIClient.shared.get(
            path: "x/player/wbi/playurl",
            params: params,
            requiresWBI: true
        )
    }

    /// 正常网页播放上下文。已登录请求完整权限，访客才启用接口提供的试看。
    /// 不伪造设备指纹，服务端返回风控挑战时直接呈现错误。
    static func playbackContextParams(isLoggedIn: Bool) -> [String: String] {
        var params = [
            "gaia_source": "pre-load",
            "web_location": "1315873",
            "voice_balance": "0"
        ]
        if !isLoggedIn { params["try_look"] = "1" }
        return params
    }

    /// 其他网页列表接口沿用的旧请求字段；播放取流不使用这些合成值。
    static func fingerprintParams() -> [String: String] {
        [
            "dm_img_list": "[]",
            "dm_img_str": randomFingerprint(minimumBytes: 16, maximumBytes: 64),
            "dm_cover_img_str": randomFingerprint(minimumBytes: 32, maximumBytes: 128),
            "dm_img_inter": #"{"ds":[],"wh":[0,0,0],"of":[0,0,0]}"#
        ]
    }

    /// 网页播放器上报的是一段 WebGL 采样数据，长度不固定。
    /// 我们没有那份数据，用等长的随机串代替即可，服务端只看格式。
    private static func randomFingerprint(minimumBytes: Int, maximumBytes: Int) -> String {
        let count = Int.random(in: minimumBytes...maximumBytes)
        let bytes = (0..<count).map { _ in UInt8.random(in: .min ... .max) }
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
    }

    private static func isUnsupportedPlayFormat(_ error: Error) -> Bool {
        guard let biliError = error as? BiliAPIError,
              case .apiError(let code, _) = biliError
        else { return false }
        return code == -400
    }
}
