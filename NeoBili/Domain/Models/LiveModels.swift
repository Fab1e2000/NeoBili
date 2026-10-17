import Foundation

/// 推荐、关注和房间详情共用的只读直播摘要。
public struct LiveRoom: Identifiable, Hashable, Sendable, Decodable {
    public let roomID: Int
    public let title: String
    public let username: String
    public let uid: Int
    public let coverURL: URL?
    public let faceURL: URL?
    public let online: Int
    public let areaName: String
    public let liveStatus: Int
    public let description: String?
    public let announcement: String?

    public var id: Int { roomID }
    public var isLive: Bool { liveStatus == 1 }
    public var uname: String { username }
    public var avatarURL: URL? { faceURL }

    public init(roomID: Int, title: String, username: String, uid: Int = 0,
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

    public init(from decoder: Decoder) throws {
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

public struct LiveRoomPage: Sendable, Equatable {
    public let rooms: [LiveRoom]
    public let page: Int
    public let hasMore: Bool
    public let total: Int?
    /// IDs before an endpoint filters offline rooms, for pagination loop checks.
    public let sourceRoomIDs: [Int]?

    public init(rooms: [LiveRoom], page: Int, hasMore: Bool, total: Int? = nil, sourceRoomIDs: [Int]? = nil) {
        self.rooms = rooms
        self.page = page
        self.hasMore = hasMore
        self.total = total
        self.sourceRoomIDs = sourceRoomIDs
    }
}

public struct LiveQuality: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String

    public static func defaultName(for quality: Int) -> String {
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

    public init(
        id: Int,
        name: String
    ) {
        self.id = id
        self.name = name
    }
}

public struct LiveStreamCandidate: Identifiable, Hashable, Sendable {
    public let url: URL
    public let protocolName: String
    public let formatName: String
    public let codecName: String
    public let quality: Int
    public var headers: [String: String] = [:]
    public var id: String { url.absoluteString }
    public var isHLS: Bool { protocolName == "http_hls" || url.pathExtension.lowercased() == "m3u8" }

    public init(
        url: URL,
        protocolName: String,
        formatName: String,
        codecName: String,
        quality: Int,
        headers: [String: String] = [:]
    ) {
        self.url = url
        self.protocolName = protocolName
        self.formatName = formatName
        self.codecName = codecName
        self.quality = quality
        self.headers = headers
    }
}

public struct LivePlayback: Sendable, Equatable {
    public let roomID: Int
    public let liveStatus: Int
    public let isPortrait: Bool
    public let qualities: [LiveQuality]
    public let candidates: [LiveStreamCandidate]
    public var isLive: Bool { liveStatus == 1 }

    public init(
        roomID: Int,
        liveStatus: Int,
        isPortrait: Bool,
        qualities: [LiveQuality],
        candidates: [LiveStreamCandidate]
    ) {
        self.roomID = roomID
        self.liveStatus = liveStatus
        self.isPortrait = isPortrait
        self.qualities = qualities
        self.candidates = candidates
    }
}

/// 直播历史接口同时返回数字与字符串ID；容错限定在这些已知字段。
public struct LiveCodingKey: CodingKey {
    public let stringValue: String
    public var intValue: Int? { nil }
    public init(_ value: String) { stringValue = value }
    public init?(stringValue: String) { self.stringValue = stringValue }
    public init?(intValue: Int) { return nil }
}

extension KeyedDecodingContainer where Key == LiveCodingKey {
    public func liveString(_ names: String...) -> String? {
        for name in names {
            let key = LiveCodingKey(name)
            if let value = try? decode(String.self, forKey: key), !value.isEmpty { return value }
            if let value = try? decode(Int.self, forKey: key) { return String(value) }
        }
        return nil
    }

    public func liveInt(_ names: String...) -> Int? {
        for name in names {
            let key = LiveCodingKey(name)
            if let value = try? decode(Int.self, forKey: key) { return value }
            if let value = try? decode(String.self, forKey: key), let integer = Int(value) { return integer }
            if let value = try? decode(Bool.self, forKey: key) { return value ? 1 : 0 }
        }
        return nil
    }
}

public func liveImageURL(_ string: String?) -> URL? {
    guard let string, !string.isEmpty else { return nil }
    let normalized = string.hasPrefix("//") ? "https:" + string : string
    guard var components = URLComponents(string: normalized),
          let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
          components.host != nil else { return nil }
    components.scheme = "https"
    return components.url
}
