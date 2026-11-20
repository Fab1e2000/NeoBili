import Foundation

/// 直播弹幕协议解析结果。解析是纯 CPU 工作，在数据层的主线程之外完成；
/// 展示模型只应用结果，不再接触原始 JSON。
public struct LiveDanmakuMessagePayload: Sendable, Equatable {
    public struct Medal: Sendable, Equatable {
        public let name: String
        public let level: Int

        public init(name: String, level: Int) {
            self.name = name
            self.level = level
        }
    }

    public let name: String
    public let text: String
    /// 服务端下发的弹幕颜色（ARGB）；nil 用默认白色。
    public let color: UInt32?
    public let emoteURL: URL?
    public let emoteWidth: Int
    public let emoteHeight: Int
    public let medal: Medal?

    public init(name: String, text: String, color: UInt32?, emoteURL: URL?,
                emoteWidth: Int, emoteHeight: Int, medal: Medal?) {
        self.name = name
        self.text = text
        self.color = color
        self.emoteURL = emoteURL
        self.emoteWidth = emoteWidth
        self.emoteHeight = emoteHeight
        self.medal = medal
    }
}

/// 醒目留言的原始字段；颜色保持服务端十六进制字符串，由展示层决定回退值。
public struct LiveDanmakuSuperChatPayload: Sendable, Equatable {
    public let id: Int
    public let price: Int
    public let message: String
    public let userName: String
    public let faceURL: URL?
    public let start: Double
    public let end: Double
    public let backgroundColor: String?
    public let bottomColor: String?
    public let priceColor: String?
    public let fontColor: String?

    public init(id: Int, price: Int, message: String, userName: String, faceURL: URL?,
                start: Double, end: Double, backgroundColor: String?, bottomColor: String?,
                priceColor: String?, fontColor: String?) {
        self.id = id
        self.price = price
        self.message = message
        self.userName = userName
        self.faceURL = faceURL
        self.start = start
        self.end = end
        self.backgroundColor = backgroundColor
        self.bottomColor = bottomColor
        self.priceColor = priceColor
        self.fontColor = fontColor
    }
}

public enum LiveDanmakuParsedEvent: Sendable {
    case danmaku(LiveDanmakuMessagePayload)
    case superChat(LiveDanmakuSuperChatPayload)
    case superChatDeleted([Int])
}

/// op=5 的 JSON 消息。只消费 `DANMU_MSG` 与 SC；其他 cmd 按 PiliPlus 默认忽略。
public enum LiveDanmakuMessageParser {
    public static func parse(_ body: Data) -> LiveDanmakuParsedEvent? {
        guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let command = root["cmd"] as? String else { return nil }
        if command.hasPrefix("DANMU_MSG") {
            return danmaku(from: root["info"]).map(LiveDanmakuParsedEvent.danmaku)
        }
        if command == "SUPER_CHAT_MESSAGE" {
            guard let data = root["data"] as? [String: Any],
                  let payload = superChat(from: data) else { return nil }
            return .superChat(payload)
        }
        if command == "SUPER_CHAT_MESSAGE_DELETE" {
            guard let data = root["data"] as? [String: Any],
                  let ids = data["ids"] as? [Int], !ids.isEmpty else { return nil }
            return .superChatDeleted(ids)
        }
        return nil
    }

    static func danmaku(from info: Any?) -> LiveDanmakuMessagePayload? {
        guard let info = info as? [Any?], info.count > 2 else { return nil }
        let text = info[1] as? String ?? ""
        guard !text.isEmpty else { return nil }

        let legacyUser = info[2] as? [Any] ?? []
        var name = legacyUser.count > 1 ? legacyUser[1] as? String ?? "" : ""
        var medal: LiveDanmakuMessagePayload.Medal?
        var emote: URL?
        var emoteWidth = 0
        var emoteHeight = 0
        let header = info[0] as? [Any?] ?? []
        var color: UInt32? = header.count > 3 ? (header[3] as? UInt32) : nil
        if let first = info[0] as? [Any?], first.count > 15,
           let content = first[15] as? [String: Any] {
            if let user = content["user"] as? [String: Any] {
                name = (user["base"] as? [String: Any])?["name"] as? String ?? name
                if let medalValue = user["medal"] as? [String: Any],
                   let medalName = medalValue["name"] as? String, !medalName.isEmpty {
                    medal = .init(name: medalName, level: medalValue["level"] as? Int ?? 0)
                }
            }
            // extra 是一段内嵌 JSON 字符串：颜色、表情弹幕类型与表情表都在里面。
            if let extraText = content["extra"] as? String,
               let extra = try? JSONSerialization.jsonObject(with: Data(extraText.utf8)) as? [String: Any] {
                if let raw = extra["color"] as? Int { color = UInt32(bitPattern: Int32(truncatingIfNeeded: raw)) }
                let isEmote = extra["dm_type"] as? Int == 1
                if isEmote, let emotes = extra["emots"] as? [String: Any],
                   let match = emotes[text] as? [String: Any],
                   let urlString = match["url"] as? String {
                    emote = URL(string: urlString)
                    emoteWidth = match["width"] as? Int ?? 0
                    emoteHeight = match["height"] as? Int ?? 0
                }
            }
            // 大表情（整条弹幕就是一张图）在 info[0][13]。
            if emote == nil, let big = first[13] as? [String: Any],
               let urlString = big["url"] as? String, !urlString.isEmpty {
                emote = URL(string: urlString)
                emoteWidth = big["width"] as? Int ?? 0
                emoteHeight = big["height"] as? Int ?? 0
            }
        }
        guard !name.isEmpty else { return nil }
        return LiveDanmakuMessagePayload(
            name: name, text: text, color: color,
            emoteURL: emote, emoteWidth: emoteWidth, emoteHeight: emoteHeight, medal: medal
        )
    }

    /// SC 历史同样由这里解析；字段缺失沿用展示层既定回退。
    public static func superChat(from data: [String: Any]) -> LiveDanmakuSuperChatPayload? {
        guard let id = data["id"] as? Int,
              let price = data["price"] as? Int,
              let message = data["message"] as? String else { return nil }
        let userInfo = data["user_info"] as? [String: Any] ?? [:]
        let now = Date().timeIntervalSince1970
        return LiveDanmakuSuperChatPayload(
            id: id, price: price, message: message,
            userName: userInfo["uname"] as? String ?? "",
            faceURL: (userInfo["face"] as? String).flatMap(URL.init),
            start: data["start_time"] as? Double ?? now,
            end: data["end_time"] as? Double ?? now,
            backgroundColor: data["background_color"] as? String,
            bottomColor: data["background_bottom_color"] as? String,
            priceColor: data["background_price_color"] as? String,
            fontColor: data["message_font_color"] as? String
        )
    }
}
