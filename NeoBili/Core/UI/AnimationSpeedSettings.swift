import SwiftUI

/// 刷新退出、卡片原位淡入和主页面淡入的速度设置。
/// 保留原有存储键，让用户已选的速度继续生效。
enum AnimationSpeedSettings {
    static let exitSpeedKey = "neobili.feedExitSpeed"
    static let enterSpeedKey = "neobili.feedEnterSpeed"
    static let defaultSpeed = 1.0
    static let range = 0.1...10.0

    /// 主页面切换时单侧淡出/淡入的基准时长。
    ///
    /// 比刷新的淡出短得多：Tab 的高亮要等内容切完才会移动（TabView 的高亮和
    /// 内容共用同一个 selection），淡出太长就会显得"点了没反应"。
    static let tabFadeDuration: Double = 0.25

    static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : defaultSpeed
    }

    static func tabFade(speed: Double) -> Double {
        tabFadeDuration / clamped(speed)
    }
}
