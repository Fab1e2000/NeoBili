import Foundation

/// 自定义动画的固定速度倍率：进入 1.5 倍、退出 4 倍。
enum AnimationSpeedSettings {
    static let enterSpeed = 1.5
    static let exitSpeed = 4.0

    /// 主页面切换时新内容淡入的基准时长；标签高亮立即切换。
    static let tabFadeDuration: Double = 0.25

    static let tabFade = tabFadeDuration / enterSpeed
}
