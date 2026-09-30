import Foundation

/// App 推荐接口的一页。解析与筛选规则照 PiliPlus `VideoHttp.rcmdVideoListApp`：
/// 先去掉广告和不可播放的卡片，再按推荐流设置做本地过滤，不改变服务端给的顺序。
struct AppRecommendationPage: Decodable {
    let cards: [AppRecommendationCard]
    /// 原始响应中最后一个有效 idx，包括之后不展示的卡片。
    let nextCursor: Int?
    let refreshConfig: AppRecommendationRefreshConfig?
    private enum Keys: String, CodingKey { case items, idx, config }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        refreshConfig = try? container.decodeIfPresent(AppRecommendationRefreshConfig.self, forKey: .config)
        var items = try container.nestedUnkeyedContainer(forKey: .items)
        var result: [AppRecommendationCard] = []
        var cursor: Int?
        while !items.isAtEnd {
            let decoder = try items.superDecoder()
            if let fields = try? decoder.container(keyedBy: Keys.self),
               let idx = fields.integer(.idx), idx > 0 { cursor = idx }
            if let card = try? AppRecommendationCard(from: decoder) { result.append(card) }
        }
        cards = result
        nextCursor = cursor
    }

    func batch(for request: RecommendationRequest, filter: RecommendationFilter) -> RecommendationBatch {
        let next = nextCursor.flatMap { cursor in
            cursor != request.appCursor ? request.next(appCursor: cursor) : nil
        }
        return RecommendationBatch(videos: videos(filter: filter), nextRequest: next, refreshConfig: refreshConfig)
    }

    var videos: [VideoSummary] { videos(filter: .none) }

    func videos(filter: RecommendationFilter) -> [VideoSummary] {
        cards.filter { card in
            !filter.dropsOwner(card.video.owner.mid)
                && !filter.dropsZone(card.zone)
                && !filter.drops(duration: card.video.duration, view: card.video.stat.view, like: card.like,
                                 title: card.video.title, isFollowed: card.isFollowed)
        }
        .map(\.video)
    }

    /// 游标和刷新标记属于分页协议；客户端参数与登录签名、推荐反馈共用 Android HD 身份。
    static func parameters(cursor: Int, pull: Bool) -> [String: String] {
        AppClientIdentity.parameters.merging([
            "c_locale": "zh_CN", "s_locale": "zh_CN", "column": "2",
            "disable_rcmd": "0", "flush": "8", "fnval": "976", "fnver": "0", "force_host": "2",
            "fourk": "1", "guidance": "1", "https_url_req": "1", "idx": String(cursor),
            "network": "wifi", "player_net": "1", "pull": pull ? "true" : "false",
            "qn": "32", "recsys_mode": "0", "splash_id": "", "voice_balance": "0",
            "statistics": #"{"appId":5,"platform":3,"version":"2.0.1","abtest":""}"#
        ]) { _, value in value }
    }

    /// 本次启动固定的会话标识，代替 PiliPlus 写死的 `11111111`。
    private static let sessionID = String(format: "%08x", UInt32.random(in: 0...UInt32.max))

    static let userAgent = AppClientIdentity.userAgent

    /// 与签名和请求参数使用同一客户端；mid、aurora 由 APIClient 补齐。
    static func headers(buvid: String) -> [String: String] {
        ["User-Agent": userAgent,
         "buvid": buvid,
         "session_id": sessionID,
         "env": "prod",
         "app-key": AppClientIdentity.mobiApp,
         "x-bili-trace-id": traceID()]
    }

    /// 每次请求一个新的追踪号，格式与官方相同：32 位十六进制:16 位十六进制:0:0。
    static func traceID() -> String {
        func hex(_ count: Int) -> String { (0..<count).map { _ in String(Int.random(in: 0..<16), radix: 16) }.joined() }
        return "\(hex(32)):\(hex(16)):0:0"
    }

    /// 与 PiliPlus `NumUtils.parseNum` 相同：取第一个数字，带「千/万/亿」时换算。
    static func count(_ text: String?) -> Int {
        guard let text, text != "-" else { return 0 }
        let plain = text.replacingOccurrences(of: ",", with: "")
        guard let match = plain.firstMatch(of: #/([0-9.]+)([千万亿])?/#),
              let value = Double(match.1), value.isFinite, value >= 0 else { return 0 }
        let scale: Double = switch match.2 {
        case "千": 1_000
        case "万": 10_000
        case "亿": 100_000_000
        default: 1
        }
        guard value * scale < Double(Int.max) else { return 0 }
        return Int(value * scale)
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

/// 一张通过了基本筛选的 App 推荐卡片，带着本地过滤要用的原始字段。
struct AppRecommendationCard: Decodable {
    let video: VideoSummary
    /// 分区名（`args.tname`），用于分区关键词过滤。
    let zone: String?
    /// 只有推荐理由里写了点赞数时才有值。
    let like: Int?
    /// App 接口不直接给关注状态，PiliPlus 用推荐理由「已关注」「新关注」判断。
    let isFollowed: Bool

    private struct Skipped: Error {}
    private enum Key: String, CodingKey {
        case bvid, param, title, cover, desc, pubdate, dimension, text, uri, online
        case cardGoto = "card_goto", canPlay = "can_play", adInfo = "ad_info"
        case player = "player_args", args, aid, cid, duration, tname
        case upID = "up_id", upName = "up_name", upFace = "up_face", descButton = "desc_button", roomID = "room_id"
        case views = "cover_left_text_1", danmaku = "cover_left_text_2"
        case rcmdReason = "rcmd_reason", threePoint = "three_point_v2"
    }

    /// 能当视频打开的卡片。`inline_av_v2` 是官方 App 里自动播放的大卡片，内容同样是普通视频。
    private static let videoGotos: Set<String> = ["av", "vertical_av", "inline_av_v2"]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let hasAd = c.contains(.adInfo) && (try? c.decodeNil(forKey: .adInfo)) != true
        // PiliPlus 的条件：屏蔽推广（ad_av、ad_web_s 等）、没有 args 的卡片。
        guard let goto = c.text(.cardGoto), !goto.hasPrefix("ad_"), !hasAd,
              let args = try? c.nestedContainer(keyedBy: Key.self, forKey: .args),
              let param = c.integer(.param),
              let title = c.text(.title) ?? c.text(.desc), !title.isEmpty,
              let cover = c.text(.cover), !cover.isEmpty else { throw Skipped() }

        var reason = c.text(.rcmdReason)
        if reason == "竖屏" { reason = nil }
        like = reason.flatMap { $0.contains("赞") ? AppRecommendationPage.count($0) : nil }
        isFollowed = reason == "已关注" || reason == "新关注"
        zone = args.text(.tname)
        let ownerName = args.text(.upName)
            ?? (try? c.nestedContainer(keyedBy: Key.self, forKey: .descButton))?.text(.text) ?? ""
        let owner = VideoOwner(mid: args.integer(.upID) ?? 0, name: ownerName, face: args.text(.upFace) ?? "")
        let stat = VideoStat(view: AppRecommendationPage.count(c.text(.views) ?? ""),
                             danmaku: AppRecommendationPage.count(c.text(.danmaku) ?? ""), like: like ?? 0,
                             favorite: 0, coin: 0, share: 0, reply: 0)
        // 「已关注」「新关注」只作关注标记；「竖屏」已在上面去掉。
        let badge = isFollowed ? String(localized: "已关注") : reason

        var video: VideoSummary
        switch goto {
        case _ where Self.videoGotos.contains(goto):
            // 只有视频卡带「能否播放」；直播、图文卡没有这个字段。
            let player: KeyedDecodingContainer<Key>?
            if c.contains(.player), try !c.decodeNil(forKey: .player) {
                // 缺失可以用 param 补身份；已返回但格式损坏的播放参数不能视作缺失。
                player = try c.nestedContainer(keyedBy: Key.self, forKey: .player)
            } else {
                player = nil
            }
            let aid = player?.integer(.aid) ?? param
            guard c.integer(.canPlay) == 1, aid > 0,
                  let bvid = c.text(.bvid) ?? AppRecommendationPage.bvid(aid: aid), !bvid.isEmpty else { throw Skipped() }
            // 缺 cid 的卡照 PiliPlus 保留，点开时由视频页查；这里记 0。
            let cid = max(0, player?.integer(.cid) ?? 0)
            video = VideoSummary(
                bvid: bvid, aid: aid, cid: cid, title: title, pic: cover, desc: c.text(.desc) ?? "",
                duration: max(0, player?.integer(.duration) ?? 0), pubdate: c.integer(.pubdate) ?? 0,
                owner: owner, stat: stat,
                dimension: try? c.decodeIfPresent(VideoDimension.self, forKey: .dimension)
            )
            video.recommendationFeedback = Self.feedbackOptions(c, goto: goto, param: param)
            video.recommendationBadge = badge
        case "live":
            // PiliPlus 要求 can_play 为 1，直播卡没有这个字段，所以它实际不显示直播卡。
            let roomID = args.integer(.roomID) ?? param
            guard roomID > 0 else { throw Skipped() }
            let room = LiveRoom(roomID: roomID, title: title, username: ownerName, uid: owner.mid,
                                coverURL: URL.biliSecure(cover), online: args.integer(.online) ?? 0,
                                areaName: zone ?? "")
            video = Self.card(id: "live-\(roomID)", title: title, cover: cover, owner: owner, stat: stat)
            video.recommendationTarget = .live(room)
            video.recommendationBadge = badge
        case "picture":
            // 图文卡的动态编号优先从跳转地址里取，取不到再用 param（照 PiliPlus 用 uri 跳转）。
            let id = Self.dynamicID(from: c.text(.uri)) ?? String(param)
            video = Self.card(id: "dynamic-\(id)", title: title, cover: cover, owner: owner, stat: stat)
            video.recommendationTarget = .dynamic(id: id)
            video.recommendationBadge = [String(localized: "动态"), badge].compactMap { $0 }.joined(separator: " · ")
        default:
            // 番剧、专栏等 NeoBili 还打不开的卡片。
            throw Skipped()
        }
        self.video = video
    }

    /// 直播、图文卡借用视频卡片的外观；编号只用来区分卡片，不能当视频打开。
    private static func card(id: String, title: String, cover: String, owner: VideoOwner, stat: VideoStat) -> VideoSummary {
        VideoSummary(bvid: id, aid: 0, cid: 0, title: title, pic: cover, desc: "", duration: 0, pubdate: 0,
                     owner: owner, stat: stat)
    }

    /// `bilibili://following/detail/123`、`bilibili://opus/detail/123`、`https://t.bilibili.com/123` 里的动态编号。
    static func dynamicID(from uri: String?) -> String? {
        guard let uri,
              let match = uri.firstMatch(of: #/(?:following/detail|opus/detail|opus|t\.bilibili\.com)/([0-9]+)/#) else { return nil }
        return String(match.1)
    }

    private static func feedbackOptions(_ c: KeyedDecodingContainer<Key>, goto: String, param: Int)
        -> RecommendationFeedbackOptions? {
        guard var entries = try? c.nestedUnkeyedContainer(forKey: .threePoint) else { return nil }
        var options = RecommendationFeedbackOptions(goto: goto, param: param)
        while !entries.isAtEnd {
            // superDecoder 无论解析成败都会前进一项，不会卡在坏数据上。
            guard let decoder = try? entries.superDecoder() else { break }
            guard let entry = try? ThreePointEntry(from: decoder) else { continue }
            switch entry.type {
            case "dislike": options.dislikeReasons = entry.reasons
            case "feedback": options.feedbacks = entry.reasons
            default: break
            }
        }
        return options
    }
}

private struct ThreePointEntry: Decodable {
    let type: String?
    let reasons: [RecommendationFeedbackOptions.Reason]?
}

private extension KeyedDecodingContainer {
    func integer(_ key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) { return value }
        return (try? decode(String.self, forKey: key)).flatMap(Int.init)
    }
    func text(_ key: Key) -> String? { try? decode(String.self, forKey: key) }
}

/// 服务端秒数；缺失事件字段才回退到旧版 auto_refresh_time，0/负数/坏值明确关闭该事件。
struct AppRecommendationRefreshConfig: Decodable, Equatable, Sendable {
    enum Trigger { case active, appear, behavior }
    let active: TimeInterval?
    let appear: TimeInterval?
    let behavior: TimeInterval?

    private enum Keys: String, CodingKey {
        case legacy = "auto_refresh_time"
        case active = "auto_refresh_time_by_active"
        case appear = "auto_refresh_time_by_appear"
        case behavior = "auto_refresh_time_by_behavior"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        func interval(_ key: Keys) -> TimeInterval? {
            let value = c.integer(c.contains(key) ? key : .legacy)
            return value.flatMap { $0 > 0 ? TimeInterval($0) : nil }
        }
        active = interval(.active)
        appear = interval(.appear)
        behavior = interval(.behavior)
    }

    func interval(for trigger: Trigger) -> TimeInterval? {
        switch trigger {
        case .active: active
        case .appear: appear
        case .behavior: behavior
        }
    }
}
