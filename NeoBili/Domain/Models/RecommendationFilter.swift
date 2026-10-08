import Foundation

/// 与 PiliPlus「推荐流设置」相同的本地过滤：推荐拿回来后按这些条件丢掉卡片。
/// 默认全部不过滤，已关注 UP 默认豁免；改动从下一次请求推荐开始生效。
struct RecommendationFilter {
    static let minDurationKey = "neobili.rcmd.minDuration"
    static let minPlayKey = "neobili.rcmd.minPlay"
    static let minLikeRatioKey = "neobili.rcmd.minLikeRatio"
    static let titleBanWordKey = "neobili.rcmd.banWordForTitle"
    static let zoneBanWordKey = "neobili.rcmd.banWordForZone"
    static let exemptFollowedKey = "neobili.rcmd.exemptFollowed"
    /// 在推荐卡片菜单里拉黑的 UP 主，照 PiliPlus 存在本地，之后的推荐里不再出现。
    static let blockedMidsKey = "neobili.rcmd.blockedMids"
    /// 首页用 App 推荐（默认）还是网页推荐。
    static let appRecommendKey = "neobili.rcmd.useApp"
    /// 刷新时保留上次内容、显示「上次看到这里」，两项默认开启。
    static let keepLastDataKey = "neobili.rcmd.keepLastData"
    static let lastSeenTipKey = "neobili.rcmd.lastSeenTip"

    static let durationOptions = [0, 30, 60, 90, 120]
    static let playOptions = [0, 50, 100, 500, 1000]
    static let likeRatioOptions = [0, 1, 2, 3, 4]

    /// 秒。
    var minDuration = 0
    var minPlay = 0
    /// 百分比：点赞数 ÷ 播放量低于它就过滤。
    var minLikeRatio = 0
    var titleBanWord: NSRegularExpression?
    var zoneBanWord: NSRegularExpression?
    var exemptFollowed = true
    var blockedMids: Set<Int> = []

    static let none = RecommendationFilter()

    static func current(_ defaults: UserDefaults = .standard) -> RecommendationFilter {
        RecommendationFilter(
            minDuration: defaults.integer(forKey: minDurationKey),
            minPlay: defaults.integer(forKey: minPlayKey),
            minLikeRatio: defaults.integer(forKey: minLikeRatioKey),
            titleBanWord: pattern(defaults.string(forKey: titleBanWordKey)),
            zoneBanWord: pattern(defaults.string(forKey: zoneBanWordKey)),
            exemptFollowed: defaults.object(forKey: exemptFollowedKey) as? Bool ?? true,
            blockedMids: Set(defaults.array(forKey: blockedMidsKey) as? [Int] ?? [])
        )
    }

    /// 拉黑成功后记下这个 UP 主。
    static func block(_ mid: Int, defaults: UserDefaults = .standard) {
        var mids = Set(defaults.array(forKey: blockedMidsKey) as? [Int] ?? [])
        mids.insert(mid)
        defaults.set(mids.sorted(), forKey: blockedMidsKey)
    }

    /// PiliPlus 先按黑名单去掉，再看分区和其它条件；黑名单不受已关注豁免影响。
    func dropsOwner(_ mid: Int) -> Bool {
        mid > 0 && blockedMids.contains(mid)
    }

    /// 关键词用 `|` 隔开，按正则、不区分大小写匹配；写错的正则视为不过滤。
    static func pattern(_ text: String?) -> NSRegularExpression? {
        guard let text, !text.isEmpty else { return nil }
        return try? NSRegularExpression(pattern: text, options: .caseInsensitive)
    }

    /// 分区关键词不受已关注豁免影响，先于其他条件判断。
    func dropsZone(_ zone: String?) -> Bool {
        guard let zone, let zoneBanWord else { return false }
        return zoneBanWord.matches(zone)
    }

    /// `like` 只有推荐理由里带点赞数时才有；没有就不按点赞率过滤。
    func drops(duration: Int, view: Int, like: Int?, title: String, isFollowed: Bool) -> Bool {
        if isFollowed && exemptFollowed { return false }
        if duration > 0 && duration < minDuration { return true }
        if view > -1 && view < minPlay { return true }
        if let like, like > -1, like * 100 < minLikeRatio * view { return true }
        return titleBanWord?.matches(title) ?? false
    }
}

private extension NSRegularExpression {
    func matches(_ text: String) -> Bool {
        firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
