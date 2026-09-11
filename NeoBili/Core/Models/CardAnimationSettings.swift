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
        case .search, .space: [.enter]
        case .relatedVideos: [] // Detail recommendations always appear immediately.
        case .favorites, .history, .watchLater: [.exit]
        case .collection: [] // The collection picker uses native interactions.
        }
    }

    var title: String {
        switch self {
        case .recommendation: "推荐页"
        case .relatedVideos: "视频详情页"
        case .search: "搜索页"
        case .space: "UP 主空间"
        case .favorites: "收藏"
        case .history: "历史记录"
        case .watchLater: "稍后再看"
        case .collection: "合集"
        case .live: "直播卡片"
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

    static func isEnabled(
        category: CardAnimationCategory,
        phase: CardAnimationPhase,
        source: VideoCardAnimationSource? = nil,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard value(for: masterKey, defaults: defaults) else { return false }
        if category == .video, let source,
           let override = defaults.object(forKey: storageKey(source: source, phase: phase)) as? Bool {
            return override
        }
        // Upgrades preserve existing choices until that page is configured.
        return value(for: storageKey(category: category, phase: phase), defaults: defaults)
    }

    private static func value(for key: String, defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultValue
    }

    /// Race the animation deadline with preference changes. Disabling an effect
    /// releases its staged content immediately, without leaving a sleeping task.
    static func waitWhileEnabled(
        for seconds: TimeInterval,
        category: CardAnimationCategory,
        phase: CardAnimationPhase,
        source: VideoCardAnimationSource? = nil
    ) async throws {
        try Task.checkCancellation()
        guard seconds > 0, seconds.isFinite, isEnabled(category: category, phase: phase, source: source) else { return }
        // Register before launching tasks so a setting changed this turn cannot
        // be missed between the enabled check and awaiting the next event.
        let changes = NotificationCenter.default.notifications(named: didChangeNotification)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await Task.sleep(for: .seconds(seconds)) }
            group.addTask {
                guard isEnabled(category: category, phase: phase, source: source) else { return }
                for await _ in changes {
                    try Task.checkCancellation()
                    if !isEnabled(category: category, phase: phase, source: source) { return }
                }
            }
            defer { group.cancelAll() }
            _ = try await group.next()
        }
        try Task.checkCancellation()
    }
}
