import Foundation

enum DanmakuSettings {
    static let fontScaleKey = "danmaku.fontScale"
    static let opacityKey = "danmaku.opacity"
    static let blockTopKey = "danmaku.blockTop"
    static let blockBottomKey = "danmaku.blockBottom"
    static let coloredEnabledKey = "danmaku.colored.enabled"
    static let videoEnabledKey = "danmaku.video.enabled"
    static let liveEnabledKey = "danmaku.live.enabled"
    static let defaultValue = true

    static func isEnabled(_ defaults: UserDefaults = .standard, key: String) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultValue
    }
}
