import Foundation

/// App 推荐卡片适配为既有 VideoSummary，不改变首页排序与刷新行为。
struct AppRecommendationPage: Decodable {
    let videos: [VideoSummary]
    private enum Keys: String, CodingKey { case items }

    init(from decoder: Decoder) throws {
        var items = try decoder.container(keyedBy: Keys.self).nestedUnkeyedContainer(forKey: .items)
        var result: [VideoSummary] = []
        while !items.isAtEnd {
            let decoder = try items.superDecoder()
            if let card = try? AppRecommendationCard(from: decoder), let video = card.video { result.append(video) }
        }
        videos = result
    }

    static func parameters(freshIndex: Int) -> [String: String] {
        ["build": "8430300", "c_locale": "zh_CN", "s_locale": "zh_CN", "channel": "master",
         "column": "2", "device": "phone", "device_name": "android", "device_type": "0",
         "disable_rcmd": "0", "flush": "8", "fnval": "976", "fnver": "0", "force_host": "2",
         "fourk": "1", "guidance": "1", "https_url_req": "1", "idx": String(freshIndex),
         "mobi_app": "android_i", "network": "wifi", "platform": "android", "player_net": "1",
         "pull": freshIndex == 0 ? "true" : "false", "qn": "32", "recsys_mode": "0",
         "splash_id": "", "voice_balance": "0",
         "statistics": #"{"appId":1,"platform":3,"version":"8.43.0","abtest":""}"#]
    }

    /// App 只给出格式化后的计数，按其精度恢复数值供既有卡片显示。
    static func count(_ text: String?) -> Int {
        guard let text else { return 0 }
        let number = text.replacingOccurrences(of: ",", with: "")
            .prefix { ($0 >= "0" && $0 <= "9") || $0 == "." }
        let scale: Double = text.contains("亿") ? 100_000_000 : (text.contains("万") ? 10_000 : 1)
        guard let value = Double(number), value.isFinite, value >= 0,
              value * scale < Double(Int.max) else { return 0 }
        return Int((value * scale).rounded())
    }

    /// 与 PiliPlus IdUtils.av2bv 相同的 BVID 编码规则，避免逐张补查详情。
    static func bvid(aid: Int) -> String? {
        guard aid > 0, aid < (1 << 51) else { return nil }
        let alphabet = Array("FcwAPNKTMug3GV5Lj7EJnHpWsx4tb8haYeviqBz6rkCy12mUSDQX9RdoZf")
        var result = Array("BV1000000000")
        var value = ((1 << 51) | aid) ^ 23442827791579
        var index = result.count - 1
        while value > 0 {
            result[index] = alphabet[value % 58]
            value /= 58
            index -= 1
        }
        result.swapAt(3, 9)
        result.swapAt(4, 7)
        return String(result)
    }
}

private struct AppRecommendationCard: Decodable {
    let video: VideoSummary?
    private enum Key: String, CodingKey {
        case goto, bvid, param, title, cover, desc, pubdate, dimension
        case cardGoto = "card_goto", canPlay = "can_play", adInfo = "ad_info"
        case player = "player_args", args, aid, cid, duration
        case upID = "up_id", upName = "up_name", upFace = "up_face"
        case views = "cover_left_text_1", danmaku = "cover_left_text_2", trackID = "track_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let hasAd = c.contains(.adInfo) && (try? c.decodeNil(forKey: .adInfo)) != true
        guard c.text(.goto) == "av", c.integer(.canPlay) == 1,
              !(c.text(.cardGoto) ?? "").hasPrefix("ad"),
              !hasAd else { video = nil; return }
        let player = try c.nestedContainer(keyedBy: Key.self, forKey: .player)
        let args = try c.nestedContainer(keyedBy: Key.self, forKey: .args)
        guard let aid = player.integer(.aid) ?? c.integer(.param), aid > 0,
              let bvid = c.text(.bvid) ?? AppRecommendationPage.bvid(aid: aid), !bvid.isEmpty,
              let cid = player.integer(.cid), cid > 0,
              let title = c.text(.title), !title.isEmpty, let cover = c.text(.cover), !cover.isEmpty else {
            video = nil; return
        }
        video = VideoSummary(
            bvid: bvid, aid: aid, cid: cid, title: title, pic: cover, desc: c.text(.desc) ?? "",
            duration: max(0, player.integer(.duration) ?? 0), pubdate: c.integer(.pubdate) ?? 0,
            owner: VideoOwner(mid: args.integer(.upID) ?? 0, name: args.text(.upName) ?? "", face: args.text(.upFace) ?? ""),
            stat: VideoStat(view: AppRecommendationPage.count(c.text(.views)),
                            danmaku: AppRecommendationPage.count(c.text(.danmaku)), like: 0,
                            favorite: 0, coin: 0, share: 0, reply: 0),
            dimension: try? c.decodeIfPresent(VideoDimension.self, forKey: .dimension),
            recommendationTrackID: c.text(.trackID)
        )
    }
}

private extension KeyedDecodingContainer {
    func integer(_ key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) { return value }
        return (try? decode(String.self, forKey: key)).flatMap(Int.init)
    }
    func text(_ key: Key) -> String? { try? decode(String.self, forKey: key) }
}
