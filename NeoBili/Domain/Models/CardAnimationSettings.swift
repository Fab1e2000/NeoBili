import Foundation

enum CardAnimationCategory: String, CaseIterable, Sendable {
    case video, dynamic, page
}

enum CardAnimationPhase: String, Sendable {
    case enter, exit
}

enum VideoCardAnimationSource: String, CaseIterable, Identifiable, Sendable {
    case recommendation, relatedVideos, search, space, favorites, history, watchLater, collection, live

    var id: String { rawValue }

    var supportedPhases: [CardAnimationPhase] {
        switch self {
        case .recommendation, .live: [.enter, .exit]
        case .search: [.enter]
        case .space: []
        case .relatedVideos: [] // Detail recommendations always appear immediately.
        case .favorites, .history, .watchLater: []
        case .collection: [] // The collection picker uses native interactions.
        }
    }

    var title: String {
        switch self {
        case .recommendation: String(localized: "推荐页")
        case .relatedVideos: String(localized: "视频详情页")
        case .search: String(localized: "搜索页")
        case .space: String(localized: "UP 主空间")
        case .favorites: String(localized: "收藏")
        case .history: String(localized: "历史记录")
        case .watchLater: String(localized: "稍后再看")
        case .collection: String(localized: "合集")
        case .live: String(localized: "直播卡片")
        }
    }
}

/// Only app-authored card effects use these preferences. System navigation,
/// menus and other native control interactions keep their normal behavior.
enum CardAnimationSettings {
    static let masterKey = "neobili.cardAnimationsEnabled"
    static let videoEnterKey = "neobili.videoCardEnterAnimation"
    static let videoExitKey = "neobili.videoCardExitAnimation"
    static let dynamicEnterKey = "neobili.dynamicCardEnterAnimation"
    static let dynamicExitKey = "neobili.dynamicCardExitAnimation"
    /// 关注页刷新完成后整列淡入。与已下线的单卡进入动画（dynamicEnterKey）分开存，旧值不影响它。
    static let dynamicRefreshEnterKey = "neobili.dynamicRefreshEnterAnimation"
    static let pageEnterKey = "neobili.pageEnterAnimation"
    static let defaultValue = true
    static let didChangeNotification = Notification.Name("neobili.cardAnimationsDidChange")

    static func storageKey(source: VideoCardAnimationSource, phase: CardAnimationPhase) -> String {
        "neobili.videoCardAnimation.\(source.rawValue).\(phase.rawValue)"
    }

    static func storageKey(category: CardAnimationCategory, phase: CardAnimationPhase) -> String {
        switch (category, phase) {
        case (.video, .enter): videoEnterKey
        case (.video, .exit): videoExitKey
        case (.dynamic, .enter): dynamicEnterKey
        case (.dynamic, .exit): dynamicExitKey
        case (.page, _): pageEnterKey
        }
    }

    /// Entrance effects are a page capability, not a preference. Old saved
    /// overrides cannot re-enable them on pages where the effect was removed.
    static func supports(category: CardAnimationCategory, phase: CardAnimationPhase,
                         source: VideoCardAnimationSource?) -> Bool {
        switch category {
        case .video: return source?.supportedPhases.contains(phase) == true
        case .dynamic: return phase == .exit
        case .page: return true
        }
    }

}
