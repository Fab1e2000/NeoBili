import Foundation

extension BiliAPI {
    /// 发送一条视频弹幕（`x/v2/dm/post`），参数与 PiliPlus 一致。返回服务器分配的弹幕 id。
    ///
    /// - Parameters:
    ///   - mode: 1 滚动、4 底部、5 顶部。
    ///   - progress: 弹幕出现在视频里的时间（秒）。
    @discardableResult
    static func shootDanmaku(cid: Int, bvid: String, message: String, progress: TimeInterval, mode: Int) async throws -> Int? {
        let csrf = await DeviceIdentity.shared.csrfToken ?? ""
        let result: DanmakuPostResult = try await APIClient.shared.post(path: "x/v2/dm/post", form: [
            "type": "1",
            "oid": String(cid),
            "bvid": bvid,
            "msg": message,
            "mode": String(mode),
            "progress": String(Int(max(0, progress) * 1000)),
            "color": "16777215",
            "fontsize": "25",
            "pool": "0",
            // 带上 rnd 时发送冷却是 5 秒，不带是 90 秒。
            "rnd": String(Int(Date().timeIntervalSince1970 * 1_000_000)),
            "csrf": csrf
        ])
        return result.dmid
    }
}

/// 发送弹幕的返回；成功时服务器可能不带 data，字段全部可选。
struct DanmakuPostResult: Decodable {
    let dmid: Int?
}
