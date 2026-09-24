import Foundation

/// 界面语言：跟随系统、简体中文或英文。
///
/// 通过应用级的 `AppleLanguages` 覆盖系统语言，由系统的本地化机制统一生效，
/// 所以切换后需要重新打开 App。B 站返回的内容（标题、评论、热搜等）不受影响。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, simplifiedChinese, english

    static let storageKey = "neobili.appLanguage"
    private static let overrideKey = "AppleLanguages"

    var id: String { rawValue }

    /// 语言本身的名字不翻译，任何界面语言下都显示成它自己的写法。
    var title: String {
        switch self {
        case .system: String(localized: "跟随系统")
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }

    private var code: String? {
        switch self {
        case .system: nil
        case .simplifiedChinese: "zh-Hans"
        case .english: "en"
        }
    }

    static var stored: AppLanguage {
        UserDefaults.standard.string(forKey: storageKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// 本次启动实际使用的语言。设置改动要到下次启动才生效，界面据此提示。
    static let launched = stored

    /// 保存选择并写入下次启动使用的语言覆盖。
    static func apply(_ language: AppLanguage) {
        let defaults = UserDefaults.standard
        defaults.set(language.rawValue, forKey: storageKey)
        if let code = language.code {
            defaults.set([code], forKey: overrideKey)
        } else {
            defaults.removeObject(forKey: overrideKey)
        }
    }

    /// 本次启动界面实际显示的语言。
    static var isEnglish: Bool { Bundle.main.preferredLocalizations.first == "en" }

    /// 与界面语言一致的日期格式区域。
    static var locale: Locale { Locale(identifier: isEnglish ? "en_US" : "zh_CN") }
}
