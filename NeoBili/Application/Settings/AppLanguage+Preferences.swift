#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation

extension AppLanguage {
    private static let overrideKey = "AppleLanguages"
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

}
