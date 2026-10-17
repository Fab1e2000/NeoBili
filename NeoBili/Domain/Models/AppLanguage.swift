import Foundation

/// 界面语言：跟随系统、简体中文或英文。
///
/// 通过应用级的 `AppleLanguages` 覆盖系统语言，由系统的本地化机制统一生效，
/// 所以切换后需要重新打开 App。B 站返回的内容（标题、评论、热搜等）不受影响。
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, simplifiedChinese, english

    public static let storageKey = "neobili.appLanguage"

    public var id: String { rawValue }

    /// 语言本身的名字不翻译，任何界面语言下都显示成它自己的写法。
    public var title: String {
        switch self {
        case .system: String(localized: "跟随系统")
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }

    public var code: String? {
        switch self {
        case .system: nil
        case .simplifiedChinese: "zh-Hans"
        case .english: "en"
        }
    }

    /// 本次启动界面实际显示的语言。
    public static var isEnglish: Bool { Bundle.main.preferredLocalizations.first == "en" }

    /// 与界面语言一致的日期格式区域。
    public static var locale: Locale { Locale(identifier: isEnglish ? "en_US" : "zh_CN") }
}
