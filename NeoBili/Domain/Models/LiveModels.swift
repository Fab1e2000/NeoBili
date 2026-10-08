import Foundation

/// 推荐、关注和房间详情共用的只读直播摘要。
struct LiveRoom: Identifiable, Hashable, Sendable, Decodable {
    let roomID: Int
    let title: String
    let username: String
    let uid: Int
    let coverURL: URL?
    let faceURL: URL?
    let online: Int
    let areaName: String
    let liveStatus: Int
    let description: String?
    let announcement: String?

    var id: Int { roomID }
    var isLive: Bool { liveStatus == 1 }
    var uname: String { username }
    var avatarURL: URL? { faceURL }

    init(roomID: Int, title: String, username: String, uid: Int = 0,
         coverURL: URL? = nil, faceURL: URL? = nil, online: Int = 0,
         areaName: String = "", liveStatus: Int = 1, description: String? = nil, announcement: String? = nil) {
        self.roomID = roomID
        self.title = title
        self.username = username
        self.uid = uid
        self.coverURL = coverURL
        self.faceURL = faceURL
        self.online = online
        self.areaName = areaName
        self.liveStatus = liveStatus
        self.description = description
        self.announcement = announcement
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: LiveCodingKey.self)
        roomID = values.liveInt("roomid", "room_id", "id") ?? 0
        guard roomID > 0 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "直播间缺少有效 room_id"))
        }
        title = values.liveString("title") ?? String(localized: "直播间 \(roomID)")
        username = values.liveString("uname", "username", "name") ?? String(localized: "主播")
        uid = values.liveInt("uid", "mid") ?? 0
        coverURL = liveImageURL(values.liveString("system_cover", "cover", "room_cover", "user_cover", "keyframe"))
        faceURL = liveImageURL(values.liveString("face", "uface", "avatar"))
        online = values.liveInt("online", "popularity") ?? 0
        areaName = values.liveString("area_name", "area_v2_name", "parent_area_name") ?? ""
        liveStatus = values.liveInt("live_status", "liveStatus") ?? 1
        description = values.liveString("description")
        announcement = values.liveString("announcement", "notice")
    }
}

struct LiveRoomPage: Sendable, Equatable {
    let rooms: [LiveRoom]
    let page: Int
    let hasMore: Bool
    let total: Int?
    /// IDs before an endpoint filters offline rooms, for pagination loop checks.
    let sourceRoomIDs: [Int]?

    init(rooms: [LiveRoom], page: Int, hasMore: Bool, total: Int? = nil, sourceRoomIDs: [Int]? = nil) {
        self.rooms = rooms
        self.page = page
        self.hasMore = hasMore
        self.total = total
        self.sourceRoomIDs = sourceRoomIDs
    }
}

struct LiveQuality: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String

    static func defaultName(for quality: Int) -> String {
        switch quality {
        case 80: String(localized: "流畅")
        case 150: String(localized: "高清")
        case 250: String(localized: "超清")
        case 400: String(localized: "蓝光")
        case 10000: String(localized: "原画")
        case 20000: "4K"
        case 30000: String(localized: "杜比")
        default: String(localized: "清晰度 \(quality)")
        }
    }
}

struct LiveStreamCandidate: Identifiable, Hashable, Sendable {
    let url: URL
    let protocolName: String
    let formatName: String
    let codecName: String
    let quality: Int
    var headers: [String: String] = [:]
    var id: String { url.absoluteString }
    var isHLS: Bool { protocolName == "http_hls" || url.pathExtension.lowercased() == "m3u8" }
}

struct LivePlayback: Sendable, Equatable {
    let roomID: Int
    let liveStatus: Int
    let isPortrait: Bool
    let qualities: [LiveQuality]
    let candidates: [LiveStreamCandidate]
    var isLive: Bool { liveStatus == 1 }
}

/// 直播历史接口同时返回数字与字符串ID；容错限定在这些已知字段。
struct LiveCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

extension KeyedDecodingContainer where Key == LiveCodingKey {
    func liveString(_ names: String...) -> String? {
        for name in names {
            let key = LiveCodingKey(name)
            if let value = try? decode(String.self, forKey: key), !value.isEmpty { return value }
            if let value = try? decode(Int.self, forKey: key) { return String(value) }
        }
        return nil
    }

    func liveInt(_ names: String...) -> Int? {
        for name in names {
            let key = LiveCodingKey(name)
            if let value = try? decode(Int.self, forKey: key) { return value }
            if let value = try? decode(String.self, forKey: key), let integer = Int(value) { return integer }
            if let value = try? decode(Bool.self, forKey: key) { return value ? 1 : 0 }
        }
        return nil
    }
}

func liveImageURL(_ string: String?) -> URL? {
    guard let string, !string.isEmpty else { return nil }
    let normalized = string.hasPrefix("//") ? "https:" + string : string
    guard var components = URLComponents(string: normalized),
          let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
          components.host != nil else { return nil }
    components.scheme = "https"
    return components.url
}
