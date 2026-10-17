import Foundation

extension RecommendationFilter {
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

    /// Local filtering is independent of the official account's blacklist.
    static func unblock(_ mid: Int, defaults: UserDefaults = .standard) {
        var mids = Set(defaults.array(forKey: blockedMidsKey) as? [Int] ?? [])
        mids.remove(mid)
        if mids.isEmpty { defaults.removeObject(forKey: blockedMidsKey) }
        else { defaults.set(mids.sorted(), forKey: blockedMidsKey) }
    }

}
