import Foundation

enum PlaybackWindowSettings {
    static let storageKey = "neobili.miniPlayerEnabled"
    static let defaultValue = true

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        // 底部播放器始终可用，忽略旧版本保存的悬浮小窗开关。
        true
    }
}

/// Boundaries are fractions of the host's safe movement area, not video centers.
enum MiniPlayerMovementSettings {
    static let topKey = "neobili.miniPlayerMovementTop"
    static let bottomKey = "neobili.miniPlayerMovementBottom"
    static let minimumSpan = 0.45

    static func normalized(top: Double, bottom: Double) -> (top: Double, bottom: Double) {
        let top = min(max(top.isFinite ? top : 0, 0), 1 - minimumSpan)
        let bottom = min(max(bottom.isFinite ? bottom : 1, top + minimumSpan), 1)
        return (top, bottom)
    }
}
