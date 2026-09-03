import Foundation

extension Int {
    /// 播放量、点赞数这类大数字的中文写法：1.2万、3.4亿。
    var biliCountText: String {
        if self >= 100_000_000 {
            return String(format: "%.1f亿", Double(self) / 100_000_000)
        }
        if self >= 10_000 {
            return String(format: "%.1f万", Double(self) / 10_000)
        }
        return String(self)
    }
}

struct VideoOwner: Decodable, Hashable, Sendable {
    let mid: Int
    let name: String
    let face: String
}

struct VideoStat: Decodable, Hashable, Sendable {
    let view: Int
    let danmaku: Int
    let like: Int
    let favorite: Int
    let coin: Int
    let share: Int
    let reply: Int
}

/// A single entry in a video feed (popular / recommend lists).
struct VideoSummary: Decodable, Identifiable, Hashable {
    let bvid: String
    let aid: Int
    let cid: Int
    let title: String
    let pic: String
    let desc: String
    let duration: Int
    let pubdate: Int
    let owner: VideoOwner
    let stat: VideoStat

    var id: String { bvid }

    var secureCoverURL: URL? { URL.biliSecure(pic) }
    var secureAvatarURL: URL? { URL.biliSecure(owner.face) }

    var formattedDuration: String {
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct PopularFeedPage: Decodable {
    let list: [VideoSummary]
    let noMore: Bool
    enum CodingKeys: String, CodingKey {
        case list
        case noMore = "no_more"
    }
}

struct VideoPart: Decodable, Identifiable, Hashable, Sendable {
    let cid: Int
    let page: Int
    let part: String
    let duration: Int
    var id: Int { cid }
}

struct VideoDetail: Decodable, Hashable, Sendable {
    let bvid: String
    let aid: Int
    let cid: Int
    let title: String
    let desc: String
    let pic: String
    let duration: Int
    let pubdate: Int
    let owner: VideoOwner
    let stat: VideoStat
    let pages: [VideoPart]

    var secureCoverURL: URL? { URL.biliSecure(pic) }
    var secureAvatarURL: URL? { URL.biliSecure(owner.face) }
}

// MARK: - Play URL (DASH)

struct DashStream: Decodable, Hashable, Sendable {
    let id: Int
    let baseUrl: String
    let backupUrl: [String]?
    let bandwidth: Int
    let mimeType: String
    let codecs: String
    let width: Int?
    let height: Int?
    let frameRate: String?
}

extension DashStream {
    private enum CodingKeys: String, CodingKey {
        case id, bandwidth, codecs, width, height
        case baseURL = "baseUrl"
        case baseURLSnake = "base_url"
        case backupURL = "backupUrl"
        case backupURLSnake = "backup_url"
        case mimeType = "mimeType"
        case mimeTypeSnake = "mime_type"
        case frameRate, frameRateSnake = "frame_rate"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        baseUrl = try container.decodeIfPresent(String.self, forKey: .baseURLSnake)
            ?? (try container.decode(String.self, forKey: .baseURL))
        backupUrl = try container.decodeIfPresent([String].self, forKey: .backupURLSnake)
            ?? (try container.decodeIfPresent([String].self, forKey: .backupURL))
        bandwidth = try container.decode(Int.self, forKey: .bandwidth)
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeTypeSnake)
            ?? (try container.decode(String.self, forKey: .mimeType))
        codecs = try container.decode(String.self, forKey: .codecs)
        width = try container.decodeIfPresent(Int.self, forKey: .width)
        height = try container.decodeIfPresent(Int.self, forKey: .height)
        frameRate = try container.decodeIfPresent(String.self, forKey: .frameRateSnake)
            ?? (try container.decodeIfPresent(String.self, forKey: .frameRate))
    }
}

struct DashPayload: Decodable, Hashable, Sendable {
    let duration: Int
    let video: [DashStream]
    let audio: [DashStream]
}

/// A legacy "progressive" (already muxed audio+video) stream. Requesting this
/// format instead of DASH keeps MVP playback to a single file URL, with no
/// client-side track merging required.
struct DurlItem: Decodable, Hashable, Sendable {
    let url: String
    let backupUrl: [String]?
    let length: Int?
    let size: Int?
}

extension DurlItem {
    private enum CodingKeys: String, CodingKey {
        case url, length, size
        case backupURL = "backupUrl"
        case backupURLSnake = "backup_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        backupUrl = try container.decodeIfPresent([String].self, forKey: .backupURLSnake)
            ?? (try container.decodeIfPresent([String].self, forKey: .backupURL))
        length = try container.decodeIfPresent(Int.self, forKey: .length)
        size = try container.decodeIfPresent(Int.self, forKey: .size)
    }
}

struct PlayURLData: Decodable, Hashable, Sendable {
    /// 这三个字段界面上并没有用到，而且被风控拦下时接口根本不返回它们。
    /// 设成可选之后，风控响应能正常解码，播放流程就还有机会去试其它格式，
    /// 而不是在第一步就抛出「数据解析失败」。
    let quality: Int?
    let acceptQuality: [Int]?
    let acceptDescription: [String]?
    let durl: [DurlItem]?
    let dash: DashPayload?
    /// 风控挑战。B 站拦下请求时 `code` 仍然是 0，
    /// 但 `data` 里只有这一个字段，没有任何播放地址。
    let vVoucher: String?

    /// 这次返回是被风控拦下的，不是视频本身不支持播放。
    var isRiskControlled: Bool {
        vVoucher != nil && durl == nil && dash == nil
    }

    var hasPlayableStream: Bool {
        durl?.isEmpty == false || dash != nil
    }

    enum CodingKeys: String, CodingKey {
        case quality, dash, durl
        case acceptQuality = "accept_quality"
        case acceptDescription = "accept_description"
        case vVoucher = "v_voucher"
    }
}
