import Foundation

// MARK: - 合集（ugc_season）

/// UP 主把多个稿件编成的合集。结构是「合集 → 若干 section → 若干 episode」，
/// 绝大多数合集只有一个 section，界面上直接把所有 section 的分集拉平展示。
///
/// 字段一律按可选解码：这块内容对播放不是必需的，某个字段缺失不该让整个
/// 视频详情解析失败、把页面变成错误页。
struct UgcSeason: Decodable, Hashable, Sendable {
    let id: Int?
    let title: String?
    let cover: String?
    let mid: Int?
    let sections: [UgcSeasonSection]?

    /// 拉平后的全部分集，界面只关心这一个列表。
    var episodes: [UgcSeasonEpisode] {
        (sections ?? []).flatMap { $0.episodes ?? [] }
    }
}

struct UgcSeasonSection: Decodable, Hashable, Sendable {
    let id: Int?
    let title: String?
    let episodes: [UgcSeasonEpisode]?
}

struct UgcSeasonEpisode: Decodable, Identifiable, Hashable, Sendable {
    /// 接口里的 `id` 字段。列表 ID 用下面的 `id`，两者不是一回事。
    let episodeId: Int?
    let aid: Int?
    let cid: Int?
    let bvid: String?
    let title: String?
    let arc: UgcSeasonArchive?

    enum CodingKeys: String, CodingKey {
        case episodeId = "id"
        case aid, cid, bvid, title, arc
    }

    var secureCoverURL: URL? { arc?.pic.flatMap { URL.biliSecure($0) } }

    var formattedDuration: String {
        guard let duration = arc?.duration, duration > 0 else { return "" }
        return String(format: "%d:%02d", duration / 60, duration % 60)
    }

    /// 分集本身没有独立 id 时用 bvid 兜底，避免多条记录共用同一个列表 ID。
    var id: String { bvid ?? String(episodeId ?? aid ?? 0) }
}

extension UgcSeasonEpisode: VideoDimensionProviding {
    var dimension: VideoDimension? { arc?.dimension }
}

/// 分集自带的稿件信息，封面和时长都在这里，不需要再逐条请求详情。
struct UgcSeasonArchive: Decodable, Hashable, Sendable {
    let pic: String?
    let duration: Int?
    let stat: UgcSeasonStat?
    let dimension: VideoDimension?
}

struct UgcSeasonStat: Decodable, Hashable, Sendable {
    let view: Int?
}
