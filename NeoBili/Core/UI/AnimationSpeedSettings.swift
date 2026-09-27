import Foundation

/// 刷新退出、卡片原位淡入和主页面淡入的速度倍率。
/// 设置页原本可以调，现在固定为原来的默认值：进入 1.5 倍、退出 4 倍。
enum AnimationSpeedSettings {
    static let enterSpeed = 1.5
    static let exitSpeed = 4.0

    /// 主页面切换时单侧淡出/淡入的基准时长。
    ///
    /// 比刷新的淡出短得多：Tab 的高亮要等内容切完才会移动（TabView 的高亮和
    /// 内容共用同一个 selection），淡出太长就会显得"点了没反应"。
    static let tabFadeDuration: Double = 0.25

    static let tabFade = tabFadeDuration / enterSpeed
}
