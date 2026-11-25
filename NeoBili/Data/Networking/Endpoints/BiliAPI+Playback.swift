import NeoBiliDomain
import Foundation

extension BiliAPI {
    static func playerVideoInfo(bvid: String, cid: Int, client: APIClient, expectedSessionID: UUID) async throws -> PlayerVideoInfo {
        try await client.get(path: "x/player/v2", params: ["bvid": bvid, "cid": String(cid)],
                             expectedSessionID: expectedSessionID)
    }

    /// 优先请求 DASH；无可播放流或服务端返回 -400 时尝试下一组格式参数。
    /// 双轨由 PlaybackSourceBuilder.edlURL 组合，最终兼容路径请求合并流。
    static func playURL(bvid: String, cid: Int, quality: Int = 127, client: APIClient, identity: DeviceIdentity) async throws -> PlayURLData {
        let quality = String(max(1, quality))
        let formats: [[String: String]] = [
            ["qn": quality, "fnval": "4048", "fnver": "0", "fourk": "1", "otype": "json", "platform": "pc"],
            // 保留基础 DASH 能力，回退到 fnval=16。
            ["qn": quality, "fnval": "16", "fnver": "0", "fourk": "1", "otype": "json", "platform": "pc"],
            // 最后的兼容路径：服务端已经合并好的文件。
            ["qn": "64", "fnval": "1", "fnver": "0", "otype": "json", "platform": "html5", "high_quality": "1"]
        ]

        for extraParams in formats {
            do {
                let payload = try await requestPlayURL(bvid: bvid, cid: cid, extraParams: extraParams, client: client, identity: identity)
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

    /// 投屏专用取流：优先请求服务端合并好的单文件 MP4（durl），避免电视无法播放分离的 DASH 音视频轨。
    static func castPlayURL(bvid: String, cid: Int, quality: Int = 80, client: APIClient, identity: DeviceIdentity) async throws -> PlayURLData {
        let preferred = max(16, quality)
        var candidates = [preferred, 80, 64, 32]
        var seen = Set<Int>()
        candidates = candidates.filter { seen.insert($0).inserted }

        for qn in candidates {
            let extraParams: [String: String] = [
                "qn": String(qn),
                "fnval": "1",
                "fnver": "0",
                "otype": "json",
                "platform": "html5",
                "high_quality": "1"
            ]
            do {
                let payload = try await requestPlayURL(bvid: bvid, cid: cid, extraParams: extraParams, client: client, identity: identity)
                if payload.isRiskControlled {
                    throw BiliAPIError.riskControlled
                }
                if let durl = payload.durl, !durl.isEmpty {
                    return payload
                }
            } catch {
                guard Self.isUnsupportedPlayFormat(error) else { throw error }
            }
        }

        throw BiliAPIError.apiError(code: -1, message: String(localized: "该视频暂不支持投屏（未获取到兼容的合并视频流）"))
    }

    private static func requestPlayURL(
        bvid: String,
        cid: Int,
        extraParams: [String: String],
        client: APIClient, identity: DeviceIdentity
    ) async throws -> PlayURLData {
        var params = extraParams
        params["bvid"] = bvid
        params["cid"] = String(cid)
        let isLoggedIn = await identity.isLoggedIn
        params.merge(playbackContextParams(isLoggedIn: isLoggedIn)) { current, _ in current }
        return try await client.get(
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

    /// 生成旧网页列表请求使用的随机 Base64 字段，去掉末尾填充；不包含实际 WebGL 采样。
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
