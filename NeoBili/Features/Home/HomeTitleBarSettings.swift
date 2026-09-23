/// 推荐页标题栏的两种样式，设置里切换：
/// - 随内容滚动（默认）：标题和头像是列表第一行，滚走后状态栏处柔和渐隐；
/// - 固定在顶部：标题栏常驻，卡片从下面滑过（与其它主页面一致）。
enum HomeTitleBarSettings {
    static let storageKey = "neobili.homePinnedTitleBar"
    static let defaultValue = false
}
