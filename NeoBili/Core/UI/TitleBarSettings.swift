import SwiftUI

/// 推荐、搜索和资料库页面的标题栏偏好。关注、直播始终固定并使用切边背景。
enum TitleBarSettings {
    static let storageKey = "neobili.homePinnedTitleBar"
    static let defaultValue = false
    static let styleKey = "neobili.titleBarStyle"

    enum Style: String, CaseIterable {
        case scrolling, pinnedHard, pinnedGradient

        var isPinned: Bool { self != .scrolling }
        var scrollEdgeStyle: ScrollEdgeEffectStyle { self == .pinnedHard ? .hard : .soft }
        var title: String {
            switch self {
            case .scrolling: String(localized: "随内容滚动")
            case .pinnedHard: String(localized: "固定·切边")
            case .pinnedGradient: String(localized: "固定·渐变")
            }
        }
    }

    static func selected(_ rawValue: String, legacyPinned: Bool) -> Style {
        Style(rawValue: rawValue) ?? (legacyPinned ? .pinnedGradient : .scrolling)
    }
}

/// 缺少新偏好时兼容旧布尔值，遵循页面的 defaultAppStorage，便于隔离测试。
@propertyWrapper
struct TitleBarPreference: DynamicProperty {
    @AppStorage(TitleBarSettings.styleKey) private var storedStyle = ""
    @AppStorage(TitleBarSettings.storageKey) private var legacyPinned = TitleBarSettings.defaultValue

    var wrappedValue: TitleBarSettings.Style {
        get { TitleBarSettings.selected(storedStyle, legacyPinned: legacyPinned) }
        nonmutating set { storedStyle = newValue.rawValue }
    }

    var projectedValue: Binding<TitleBarSettings.Style> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
}
