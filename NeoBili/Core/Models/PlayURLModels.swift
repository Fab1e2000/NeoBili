import Foundation

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
    var flac: LosslessAudio? = nil
    var dolby: DolbyAudio? = nil

    struct LosslessAudio: Decodable, Hashable, Sendable { let audio: DashStream? }
    struct DolbyAudio: Decodable, Hashable, Sendable { let audio: [DashStream]? }

    var allAudio: [DashStream] {
        audio + (flac?.audio.map { [$0] } ?? []) + (dolby?.audio ?? [])
    }
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
    /// 返回档位和声明列表。风控响应可能缺少它们，保留可选解码才能
    /// 将服务端挑战准确呈现为风控错误，而不是误报「数据解析失败」。
    let quality: Int?
    let acceptQuality: [Int]?
    let acceptDescription: [String]?
    let durl: [DurlItem]?
    let dash: DashPayload?
    /// 风控挑战。B 站拦下请求时 `code` 仍然是 0，
    /// 但 `data` 里只有这一个字段，没有任何播放地址。
    let vVoucher: String?
    var supportFormats: [PlayURLSupportFormat]? = nil

    /// 服务端声明的画质列表不等于当前账号已取得的轨道；选择缺失档位时仍需按 qn 取流。
    var declaredVideoQualities: [Int] {
        var values = Set(acceptQuality ?? [])
        values.formUnion(supportFormats?.map(\.quality) ?? [])
        values.formUnion(dash?.video.filter { Self.isMediaURL($0.baseUrl) }.map(\.id) ?? [])
        if let quality, durl?.contains(where: { Self.isMediaURL($0.url) }) == true { values.insert(quality) }
        return values.filter { $0 > 0 }.sorted(by: >)
    }

    func hasVideoStream(quality: Int) -> Bool {
        if dash?.video.contains(where: { $0.id == quality && Self.isMediaURL($0.baseUrl) }) == true { return true }
        return self.quality == quality && durl?.contains(where: { Self.isMediaURL($0.url) }) == true
    }

    func preservingDeclaredQualities(from previous: PlayURLData) -> PlayURLData {
        var merged = PlayURLData(quality: quality,
            acceptQuality: Array(Set((acceptQuality ?? []) + (previous.acceptQuality ?? []))).sorted(by: >),
            acceptDescription: acceptDescription, durl: durl, dash: dash, vVoucher: vVoucher)
        var seen = Set<Int>()
        merged.supportFormats = ((supportFormats ?? []) + (previous.supportFormats ?? []))
            .filter { seen.insert($0.quality).inserted }
        return merged
    }

    private static func isMediaURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return false }
        return ["https", "http"].contains(scheme) && url.host?.isEmpty == false
    }

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
        case supportFormats = "support_formats"
    }
}

struct PlayURLSupportFormat: Decodable, Hashable, Sendable {
    let quality: Int
    let description: String?
    let needsVIP: Bool?
    let needsLogin: Bool?

    enum CodingKeys: String, CodingKey {
        case quality
        case description = "new_description"
        case needsVIP = "need_vip"
        case needsLogin = "need_login"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        quality = try values.decode(Int.self, forKey: .quality)
        description = try values.decodeIfPresent(String.self, forKey: .description)
        func flag(_ key: CodingKeys) -> Bool? {
            if let value = try? values.decode(Bool.self, forKey: key) { return value }
            if let value = try? values.decode(Int.self, forKey: key) { return value != 0 }
            return nil
        }
        needsVIP = flag(.needsVIP)
        needsLogin = flag(.needsLogin)
    }
}
