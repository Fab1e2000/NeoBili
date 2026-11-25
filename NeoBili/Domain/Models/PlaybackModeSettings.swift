import Foundation

/// 视频播放模式设置与播完决策。
///
/// - `loopEnabled`（洗脑循环）：独立开关，开启时优先单集循环当前分 P。
/// - `autoAdvanceEnabled`（自动切集 / 自动连播 vs 播完暂停）：统一开关；
///   当前视频有分 P 或合集时表现为「自动切集」（末集暂停），无分 P 且无合集时表现为「自动连播」（跳相关推荐）。
public enum PlaybackModeSettings {
    public static let loopEnabledKey = "neobili.playback.loopEnabled"
    public static let autoAdvanceEnabledKey = "neobili.playback.autoAdvanceEnabled"

    public static let defaultLoopEnabled = false
    public static let defaultAutoAdvanceEnabled = true

    public static func isLoopEnabled(in defaults: UserDefaults = .standard) -> Bool {
        if let stored = defaults.object(forKey: loopEnabledKey) as? Bool {
            return stored
        }
        return defaultLoopEnabled
    }

    public static func isAutoAdvanceEnabled(in defaults: UserDefaults = .standard) -> Bool {
        if let stored = defaults.object(forKey: autoAdvanceEnabledKey) as? Bool {
            return stored
        }
        return defaultAutoAdvanceEnabled
    }

    /// 无分 P 且无合集时显示「自动连播」，有分 P 或合集时显示「自动切集」。
    public static func autoAdvanceTitle(hasEpisodes: Bool) -> String {
        hasEpisodes ? String(localized: "自动切集") : String(localized: "自动连播")
    }

    public enum EndAction: Equatable, Sendable {
        case sleep
        case loop
        case nextPart(cid: Int)
        case nextSeasonEpisode(UgcSeasonEpisode)
        case nextOfflineEntry(id: String)
        case nextRelated(VideoSummary)
        case pause
    }

    /// 计算播完当前视频/分 P 后的下一步动作。
    ///
    /// 优先级：定时休眠「播完本集」 > 洗脑循环 > 自动切集/自动连播 > 播完暂停。
    public static func resolveEndAction(
        sleepsAfterVideoEnd: Bool,
        loopEnabled: Bool,
        autoAdvanceEnabled: Bool,
        isOffline: Bool,
        currentBvid: String,
        currentCid: Int,
        parts: [VideoPart] = [],
        season: UgcSeason? = nil,
        related: [VideoSummary] = [],
        visitedBvids: Set<String> = [],
        offlineEntryIDs: [String] = [],
        currentOfflineEntryID: String? = nil
    ) -> EndAction {
        if sleepsAfterVideoEnd {
            return .sleep
        }
        if loopEnabled {
            return .loop
        }
        guard autoAdvanceEnabled else {
            return .pause
        }

        if isOffline {
            if let currentOfflineEntryID,
               let index = offlineEntryIDs.firstIndex(of: currentOfflineEntryID),
               offlineEntryIDs.indices.contains(index + 1) {
                return .nextOfflineEntry(id: offlineEntryIDs[index + 1])
            }
            return .pause
        }

        let hasMultipleParts = parts.count > 1
        if hasMultipleParts,
           let partIndex = parts.firstIndex(where: { $0.cid == currentCid }),
           parts.indices.contains(partIndex + 1) {
            return .nextPart(cid: parts[partIndex + 1].cid)
        }

        if let season {
            let episodes = season.episodes
            if let epIndex = episodes.firstIndex(where: { $0.bvid == currentBvid }) {
                if episodes.indices.contains(epIndex + 1),
                   episodes[epIndex + 1].bvid != nil {
                    return .nextSeasonEpisode(episodes[epIndex + 1])
                }
                return .pause
            }
        }

        if hasMultipleParts {
            return .pause
        }

        var excluded = visitedBvids
        excluded.insert(currentBvid)
        if let next = related.first(where: { !$0.bvid.isEmpty && !excluded.contains($0.bvid) }) {
            return .nextRelated(next)
        }
        return .pause
    }
}
