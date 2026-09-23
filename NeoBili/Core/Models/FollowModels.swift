import Foundation

// MARK: - 关注页要展示的一条投稿

/// 「关注」页列表里的一条视频。
///
/// 动态接口和空间投稿接口返回的字段名、类型都不一样（动态的播放量是服务端
/// 排好版的「1.2万」，空间接口给的是裸数字），所以两边各自转换成这一个模型，
/// 卡片视图只认识它。
struct FollowedVideo: Identifiable, Hashable, Sendable, VideoDimensionProviding {
    /// 列表标识。动态流用动态 id（同一个稿件可能被不同动态带出来），
    /// 空间投稿列表用 bvid。
    let id: String
    let bvid: String
    let aid: Int
    let title: String
    let cover: String
    /// 已经排好版的时长，例如 `12:34`。
    let durationText: String
    /// 已经排好版的播放量，例如 `1.2万`。
    let playText: String
    let authorMid: Int
    let authorName: String
    let authorFace: String
    /// 「3小时前」这类相对时间。
    let publishedText: String
    var dimension: VideoDimension? = nil

    var secureCoverURL: URL? { URL.biliSecure(cover) }
    var secureAvatarURL: URL? { URL.biliSecure(authorFace) }
}

// MARK: - 关注的 UP 主（x/polymer/web-dynamic/v1/portal）

/// 动态页顶上那一排头像里的一个 UP 主。
struct FollowedUp: Decodable, Identifiable, Hashable, Sendable {
    let mid: Int
    let uname: String
    let face: String
    /// 有没有未读更新。头像上的小红点就是它。
    let hasUpdate: Bool
    /// 由关注直播列表补充；动态 portal 自身不保证包含开播状态。
    var liveRoomID: Int? = nil

    var id: Int { mid }
    var secureAvatarURL: URL? { URL.biliSecure(face) }

    enum CodingKeys: String, CodingKey {
        case mid, uname, face
        case hasUpdate = "has_update"
    }

    init(from decoder: Decoder) throws {
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

    init(mid: Int, uname: String, face: String, hasUpdate: Bool, liveRoomID: Int? = nil) {
        self.mid = mid
        self.uname = uname
        self.face = face
        self.hasUpdate = hasUpdate
        self.liveRoomID = liveRoomID.flatMap { $0 > 0 ? $0 : nil }
    }

    static func orderedForSidebar(_ ups: [FollowedUp], keepsPriority: (FollowedUp) -> Bool) -> [FollowedUp] {
        var live: [FollowedUp] = [], updated: [FollowedUp] = [], remaining: [FollowedUp] = []
        for up in ups {
            if up.liveRoomID != nil { live.append(up) }
            else if keepsPriority(up) { updated.append(up) }
            else { remaining.append(up) }
        }
        return live + updated + remaining
    }
}

struct DynamicPortalPayload: Decodable, Sendable {
    let upList: [FollowedUp]?

    enum CodingKeys: String, CodingKey {
        case upList = "up_list"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        upList = (try? container.decodeIfPresent(LenientList<FollowedUp>.self, forKey: .upList))??.elements
    }
}
