import Foundation

// MARK: - 合集（ugc_season）

/// UP 主把多个稿件编成的合集。结构是「合集 → 若干 section → 若干 episode」，
/// 绝大多数合集只有一个 section，界面上直接把所有 section 的分集拉平展示。
///
/// 字段一律按可选解码：这块内容对播放不是必需的，某个字段缺失不该让整个
/// 视频详情解析失败、把页面变成错误页。
public struct UgcSeason: Decodable, Hashable, Sendable {
    public let id: Int?
    public let title: String?
    public let cover: String?
    public let mid: Int?
    public let sections: [UgcSeasonSection]?

    /// 拉平后的全部分集，界面只关心这一个列表。
    public var episodes: [UgcSeasonEpisode] {
        (sections ?? []).flatMap { $0.episodes ?? [] }
    }
}

public struct UgcSeasonSection: Decodable, Hashable, Sendable {
    public let id: Int?
    public let title: String?
    public let episodes: [UgcSeasonEpisode]?
}

public struct UgcSeasonEpisode: Decodable, Identifiable, Hashable, Sendable {
    /// 接口里的 `id` 字段。列表 ID 用下面的 `id`，两者不是一回事。
    public let episodeId: Int?
    public let aid: Int?
    public let cid: Int?
    public let bvid: String?
    public let title: String?
    public let arc: UgcSeasonArchive?

    enum CodingKeys: String, CodingKey {
        case episodeId = "id"
        case aid, cid, bvid, title, arc
    }

    public var secureCoverURL: URL? { arc?.pic.flatMap { URL.biliSecure($0) } }

    public var formattedDuration: String {
        guard let duration = arc?.duration, duration > 0 else { return "" }
        return String(format: "%d:%02d", duration / 60, duration % 60)
    }

    /// 分集本身没有独立 id 时用 bvid 兜底，避免多条记录共用同一个列表 ID。
    public var id: String { bvid ?? String(episodeId ?? aid ?? 0) }
}

extension UgcSeasonEpisode: VideoDimensionProviding {
    public var dimension: VideoDimension? { arc?.dimension }
}

/// 分集自带的稿件信息，封面和时长都在这里，不需要再逐条请求详情。
public struct UgcSeasonArchive: Decodable, Hashable, Sendable {
    public let pic: String?
    public let duration: Int?
    public let stat: UgcSeasonStat?
    public let dimension: VideoDimension?
}

public struct UgcSeasonStat: Decodable, Hashable, Sendable {
    public let view: Int?
}
