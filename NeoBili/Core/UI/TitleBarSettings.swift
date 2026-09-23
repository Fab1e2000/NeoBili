/// 各主页面标题栏（标题 + 头像）的两种样式，设置里全局切换：
/// - 随内容滚动（默认）：标题行是列表内容的第一行，随内容滚走；
/// - 固定在顶部：标题行常驻顶部，内容从下面滑过。
///
/// 存储键沿用最早只作用于推荐页时的名字，旧版本保存的选择继续有效。
enum TitleBarSettings {
    static let storageKey = "neobili.homePinnedTitleBar"
    static let defaultValue = false

    static func summary(pinned: Bool) -> String { pinned ? "固定在顶部" : "随内容滚动" }
}
