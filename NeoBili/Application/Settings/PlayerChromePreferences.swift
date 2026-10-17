#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation
import Observation

/// 两组控件位置的当前值，设置页和播放器控件共用这一个对象。
///
/// 读写都经过这里：滑条改的是它，控件读的也是它，Observation 只让读到的控件重算。
/// 键名沿用 `PlayerChromeSettings.keys(for:)`，已保存的值继续有效；
/// 只写入真正改动的那一项，没动过的项仍然跟随默认值。
@MainActor @Observable
final class PlayerChromePreferences {
    private(set) var fullScreen: PlayerChromeSettings.Values
    private(set) var inline: PlayerChromeSettings.Values
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        fullScreen = Self.load(.fullScreen, from: defaults)
        inline = Self.load(.inline, from: defaults)
    }

    func values(for mode: PlayerChromeSettings.Mode) -> PlayerChromeSettings.Values {
        switch mode {
        case .fullScreen: fullScreen
        case .inline: inline
        }
    }

    func update(_ mode: PlayerChromeSettings.Mode, _ change: (inout PlayerChromeSettings.Values) -> Void) {
        let old = values(for: mode)
        var new = old
        change(&new)
        guard new != old else { return }
        switch mode {
        case .fullScreen: fullScreen = new
        case .inline: inline = new
        }
        let keys = PlayerChromeSettings.keys(for: mode)
        let fields: [(KeyPath<PlayerChromeSettings.Values, Double>, String)] = [
            (\.horizontalInset, keys.horizontalInset), (\.topInset, keys.topInset),
            (\.bottomInset, keys.bottomInset), (\.spacing, keys.spacing)
        ]
        for (field, key) in fields where new[keyPath: field] != old[keyPath: field] {
            defaults.set(new[keyPath: field], forKey: key)
        }
        if new.followsSafeArea != old.followsSafeArea, let key = keys.followsSafeArea {
            defaults.set(new.followsSafeArea, forKey: key)
        }
    }

    private static func load(_ mode: PlayerChromeSettings.Mode, from defaults: UserDefaults) -> PlayerChromeSettings.Values {
        let keys = PlayerChromeSettings.keys(for: mode)
        let fallback = PlayerChromeSettings.defaults(for: mode)
        func number(_ key: String) -> Double? {
            (defaults.object(forKey: key) as? NSNumber)?.doubleValue
        }
        let horizontal = number(keys.horizontalInset)
        var followsSafeArea = false
        var isLegacyAutomatic = false
        if let key = keys.followsSafeArea {
            if let saved = defaults.object(forKey: key) as? Bool {
                followsSafeArea = saved
            } else if let horizontal {
                // 旧版本：负数表示跟随系统，非负数是手动值。
                isLegacyAutomatic = horizontal < 0
                followsSafeArea = isLegacyAutomatic
            } else {
                followsSafeArea = fallback.followsSafeArea
            }
        }
        return PlayerChromeSettings.Values(
            horizontalInset: isLegacyAutomatic ? fallback.horizontalInset : horizontal ?? fallback.horizontalInset,
            topInset: number(keys.topInset) ?? fallback.topInset,
            bottomInset: number(keys.bottomInset) ?? fallback.bottomInset,
            spacing: number(keys.spacing) ?? fallback.spacing,
            followsSafeArea: followsSafeArea
        )
    }
}
