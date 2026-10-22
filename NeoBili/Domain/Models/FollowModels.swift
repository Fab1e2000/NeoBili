import Foundation

// MARK: - 关注页要展示的一条投稿

/// 「关注」页列表里的一条视频。
///
/// 动态接口和空间投稿接口返回的字段名、类型都不一样（动态的播放量是服务端
/// 排好版的「1.2万」，空间接口给的是裸数字），所以两边各自转换成这一个模型，
/// 卡片视图只认识它。
public struct FollowedVideo: Identifiable, Hashable, Sendable, VideoDimensionProviding {
    /// 列表标识。动态流用动态 id（同一个稿件可能被不同动态带出来），
    /// 空间投稿列表用 bvid。
    public let id: String
    public let bvid: String
    public let aid: Int
    public let title: String
    public let cover: String
    /// 已经排好版的时长，例如 `12:34`。
    public let durationText: String
    /// 已经排好版的播放量，例如 `1.2万`。
    public let playText: String
    public let authorMid: Int
    public let authorName: String
    public let authorFace: String
    /// 「3小时前」这类相对时间。
    public let publishedText: String
    public var dimension: VideoDimension? = nil

    public var secureCoverURL: URL? { URL.biliSecure(cover) }
    public var secureAvatarURL: URL? { URL.biliSecure(authorFace) }

    public init(
        id: String,
        bvid: String,
        aid: Int,
        title: String,
        cover: String,
        durationText: String,
        playText: String,
        authorMid: Int,
        authorName: String,
        authorFace: String,
        publishedText: String,
        dimension: VideoDimension? = nil
    ) {
        self.id = id
        self.bvid = bvid
        self.aid = aid
        self.title = title
        self.cover = cover
        self.durationText = durationText
        self.playText = playText
        self.authorMid = authorMid
        self.authorName = authorName
        self.authorFace = authorFace
        self.publishedText = publishedText
        self.dimension = dimension
    }
}

// MARK: - 关注的 UP 主（x/polymer/web-dynamic/v1/portal）

/// 动态页顶上那一排头像里的一个 UP 主。
public struct FollowedUp: Decodable, Identifiable, Hashable, Sendable {
    public let mid: Int
    public let uname: String
    public let face: String
    /// 有没有未读更新。头像上的小红点就是它。
    public let hasUpdate: Bool
    /// 由关注直播列表补充；动态 portal 自身不保证包含开播状态。
    public var liveRoomID: Int? = nil

    public var id: Int { mid }
    public var secureAvatarURL: URL? { URL.biliSecure(face) }

    enum CodingKeys: String, CodingKey {
        case mid, uname, face
        case hasUpdate = "has_update"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let mid = container.flexibleInt(forKey: .mid) else {
            throw DecodingError.dataCorruptedError(
                forKey: .mid,
                in: container,
                debugDescription: "关注的 UP 主必须有 mid"
            )
        }
        self.mid = mid
        uname = container.flexibleString(forKey: .uname) ?? ""
        face = container.flexibleString(forKey: .face) ?? ""
        hasUpdate = container.flexibleBool(forKey: .hasUpdate) ?? false
    }

    public init(mid: Int, uname: String, face: String, hasUpdate: Bool, liveRoomID: Int? = nil) {
        self.mid = mid
        self.uname = uname
        self.face = face
        self.hasUpdate = hasUpdate
        self.liveRoomID = liveRoomID.flatMap { $0 > 0 ? $0 : nil }
    }

    public static func orderedForSelection(_ ups: [FollowedUp], keepsPriority: (FollowedUp) -> Bool) -> [FollowedUp] {
        var live: [FollowedUp] = [], updated: [FollowedUp] = [], remaining: [FollowedUp] = []
        for up in ups {
            if up.liveRoomID != nil { live.append(up) }
            else if keepsPriority(up) { updated.append(up) }
            else { remaining.append(up) }
        }
        return live + updated + remaining
    }
}

// MARK: - 关注列表（x/relation/followings）

/// 「全部关注」的一页。条目沿用 `FollowedUp`，没有 `has_update` 时按无更新处理。
public struct FollowingsPage: Decodable, Sendable {
    public static let pageSize = 50
    public let ups: [FollowedUp]
    public let total: Int

    enum CodingKeys: String, CodingKey {
        case list, total
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ups = (try? container.decodeIfPresent(LenientList<FollowedUp>.self, forKey: .list))??.elements ?? []
        total = container.flexibleInt(forKey: .total) ?? 0
    }
}

public struct DynamicPortalPayload: Decodable, Sendable {
    public let upList: [FollowedUp]?

    enum CodingKeys: String, CodingKey {
        case upList = "up_list"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        upList = (try? container.decodeIfPresent(LenientList<FollowedUp>.self, forKey: .upList))??.elements
    }
}
