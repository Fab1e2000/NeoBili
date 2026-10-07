import Foundation

/// App 推荐接口的一页。基础解析源自 PiliPlus，广告位信息按官方响应区分：
/// 先去掉广告和不可播放的卡片，再按推荐流设置做本地过滤，不改变服务端给的顺序。
struct AppRecommendationPage: Decodable {
    let cards: [AppRecommendationCard]
    /// 原始响应中最后一个有效 idx，包括之后不展示的卡片。
    let nextCursor: Int?
    /// Only the original first item supplies the refresh head; never scan past it.
    let refreshCursor: Int?
    let refreshConfig: AppRecommendationRefreshConfig?
    let bannerHash: String?
    let exposurePolicy: RecommendationExposurePolicy
    private enum Keys: String, CodingKey { case items, idx, config }

    private enum BannerKeys: String, CodingKey { case hash; case bannerItem = "banner_item" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        exposurePolicy = (try? container.decode(RecommendationExposurePolicy.self, forKey: .config)) ?? .init()
        refreshConfig = try? container.decodeIfPresent(AppRecommendationRefreshConfig.self, forKey: .config)
        var items = try container.nestedUnkeyedContainer(forKey: .items)
        var result: [AppRecommendationCard] = []
        var cursor: Int?
        var head: Int?
        var hash: String?
        while !items.isAtEnd {
            let position = items.currentIndex + 1
            let decoder = try items.superDecoder()
            if let fields = try? decoder.container(keyedBy: Keys.self),
               let idx = fields.integer(.idx), idx > 0 {
                cursor = idx
                if position == 1 { head = idx }
            }
            if hash == nil, let banner = try? decoder.container(keyedBy: BannerKeys.self), banner.contains(.bannerItem) {
                hash = banner.text(.hash)
            }
            if var card = try? AppRecommendationCard(from: decoder) {
                card.video.recommendationPosition = position
                result.append(card)
            }
        }
        bannerHash = hash
        cards = result
        nextCursor = cursor
        refreshCursor = head
    }

    func batch(for request: RecommendationRequest, filter: RecommendationFilter) -> RecommendationBatch {
        let next = nextCursor.flatMap { cursor in
            cursor != request.appCursor ? request.next(appCursor: cursor) : nil
        }
        return RecommendationBatch(videos: videos(filter: filter), nextRequest: next, refreshConfig: refreshConfig, appCursor: nextCursor, refreshCursor: refreshCursor, exposurePolicy: exposurePolicy)
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
    var video: VideoSummary
    /// 分区名（`args.tname`），用于分区关键词过滤。
    let zone: String?
    /// 只有推荐理由里写了点赞数时才有值。
    let like: Int?
    /// App 接口不直接给关注状态，PiliPlus 用推荐理由「已关注」「新关注」判断。
    let isFollowed: Bool

    private struct Skipped: Error {}
    private enum ExtraKey: String, CodingKey { case coverID = "cover_id", isCoverTest = "is_cover_test", text }
    private enum Key: String, CodingKey {
        case bvid, param, title, cover, desc, pubdate, dimension, text, uri, online
        case cardGoto = "card_goto", canPlay = "can_play", adInfo = "ad_info"
        case player = "player_args", args, aid, cid, duration, tname
        case upID = "up_id", upName = "up_name", upFace = "up_face", descButton = "desc_button", roomID = "room_id"
        case views = "cover_left_text_1", danmaku = "cover_left_text_2"
        case rcmdReason = "rcmd_reason", threePoint = "three_point_v2"
        case trackID = "track_id", reportFlowData = "report_flow_data", cardType = "card_type", goto
        case extraRptFields = "extra_rpt_fields", rcmdReasonStyle = "rcmd_reason_style"
        case tid, rid, style, cardMaterialID = "card_material_id", cardRelID = "card_rel_id", dalaoFeature = "dalao_feature"
    }

    /// 能当视频打开的卡片。`inline_av_v2` 是官方 App 里自动播放的大卡片，内容同样是普通视频。
    private static let videoGotos: Set<String> = ["av", "vertical_av", "inline_av_v2"]

    private struct AdKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    /// 普通推荐也会带广告位归因信息；只有这些字段时不代表推广。
    /// 未识别的广告结构仍保守过滤，不能仅凭视频 goto 放行。
    private static let placementKeys: Set<String> = [
        "resource", "source", "request_id", "index", "is_ad_loc", "card_index", "client_ip"
    ]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        var hasAd = false
        if c.contains(.adInfo), (try? c.decodeNil(forKey: .adInfo)) != true {
            if let ad = try? c.nestedContainer(keyedBy: AdKey.self, forKey: .adInfo) {
                hasAd = !Set(ad.allKeys.map(\.stringValue)).isSubset(of: Self.placementKeys)
            } else { hasAd = true }
        }
        // 明确的广告 goto 始终过滤；仅广告位信息允许继续按普通卡片校验。
        guard let goto = c.text(.cardGoto), !goto.hasPrefix("ad_"), !hasAd,
              let args = try? c.nestedContainer(keyedBy: Key.self, forKey: .args),
              let param = c.integer(.param),
              let title = c.text(.title) ?? c.text(.desc), !title.isEmpty,
              let cover = c.text(.cover), !cover.isEmpty else { throw Skipped() }

        // 新版卡片（包括 large_cover_v9）可能只在样式对象中提供标签文本。
        // 保留服务器给出的完整理由，如「7万点赞 | 竖屏」，不把类型标记删掉。
        let styledReason = (try? c.nestedContainer(keyedBy: ExtraKey.self, forKey: .rcmdReasonStyle))?.text(.text)
        let reason = [styledReason, c.text(.rcmdReason)]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        like = reason.flatMap { $0.contains("赞") ? AppRecommendationPage.count($0) : nil }
        isFollowed = reason == "已关注" || reason == "新关注"
        zone = args.text(.tname)
        let ownerName = args.text(.upName)
            ?? (try? c.nestedContainer(keyedBy: Key.self, forKey: .descButton))?.text(.text) ?? ""
        let owner = VideoOwner(mid: args.integer(.upID) ?? 0, name: ownerName, face: args.text(.upFace) ?? "")
        let stat = VideoStat(view: AppRecommendationPage.count(c.text(.views) ?? ""),
                             danmaku: AppRecommendationPage.count(c.text(.danmaku) ?? ""), like: like ?? 0,
                             favorite: 0, coin: 0, share: 0, reply: 0)
        // 展示原始推荐理由；关注状态另用于过滤豁免，不替换「新关注」等文案。
        let badge = reason

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
            video.playbackEntry = .recommendation(trackID: c.text(.trackID), reportFlowData: c.text(.reportFlowData))
            video.isLargeRecommendationCard = goto == "inline_av_v2" || c.text(.cardType)?.hasPrefix("large_cover") == true
            var click = ["param": String(param), "title": title, "up_id": String(owner.mid)]
            for (key, field): (String, Key) in [("card_type", .cardType), ("goto", .goto),
                ("rcmd_reason", .rcmdReason), ("style", .style), ("card_material_id", .cardMaterialID),
                ("card_rel_id", .cardRelID), ("dalao_feature", .dalaoFeature)] {
                if let value = c.text(field) { click[key] = value }
            }
            for (key, field): (String, Key) in [("tid", .tid), ("rid", .rid)] {
                if let value = args.integer(field) { click[key] = String(value) }
            }
            click["goto"] = click["goto"] ?? goto
            if let reason = try? c.nestedContainer(keyedBy: ExtraKey.self, forKey: .rcmdReasonStyle),
               click["rcmd_reason"] == nil { click["rcmd_reason"] = reason.text(.text) }
            if let extra = try? c.nestedContainer(keyedBy: ExtraKey.self, forKey: .extraRptFields) {
                for key in [ExtraKey.coverID, .isCoverTest] {
                    if let value = extra.text(key) { click[key.rawValue] = value }
                    else if let value = extra.integer(key) { click[key.rawValue] = String(value) }
                }
            }
            video.recommendationClickFields = click
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
