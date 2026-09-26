import CoreGraphics
import Foundation
import Observation

/// 播放器控件的位置设置：全屏横屏与非全屏（视频页上的小窗、竖屏全屏）各一组，
/// 设置页可调，`PlayerGlassChrome` 实时读取。当前值由 `PlayerChromePreferences` 保存。
enum PlayerChromeSettings {
    enum Mode: String, CaseIterable, Identifiable {
        case fullScreen, inline

        var id: String { rawValue }
        var title: String { self == .fullScreen ? String(localized: "全屏") : String(localized: "非全屏") }
    }

    struct Keys {
        let horizontalInset: String
        let topInset: String
        let bottomInset: String
        let spacing: String
        /// 只有全屏有：左右边距是否跟随系统横屏安全区。
        let followsSafeArea: String?
    }

    /// 边距存的是点按区域到边缘的距离（沿用旧键）；设置页显示的是看得见的玻璃到边缘的距离，
    /// 两者相差 `tapAreaMargin`。
    struct Values: Equatable {
        var horizontalInset: Double
        var topInset: Double
        var bottomInset: Double
        var spacing: Double
        /// 只用于全屏：左右边距跟随系统横屏安全区，此时 `horizontalInset` 不生效。
        var followsSafeArea = false
    }

    /// 全屏的键沿用最早只有全屏设置时的名字，已保存的值继续有效。
    static func keys(for mode: Mode) -> Keys {
        switch mode {
        case .fullScreen:
            Keys(horizontalInset: "neobili.fullScreenChrome.horizontalInset",
                 topInset: "neobili.fullScreenChrome.topInset",
                 bottomInset: "neobili.fullScreenChrome.bottomInset",
                 spacing: "neobili.fullScreenChrome.spacing",
                 followsSafeArea: "neobili.fullScreenChrome.followsSafeArea")
        case .inline:
            Keys(horizontalInset: "neobili.inlineChrome.horizontalInset",
                 topInset: "neobili.inlineChrome.topInset",
                 bottomInset: "neobili.inlineChrome.bottomInset",
                 spacing: "neobili.inlineChrome.spacing",
                 followsSafeArea: nil)
        }
    }

    /// 点按区域（48pt）比看得见的玻璃（32pt）每边多出的距离，和 `PlayerChromeLayout` 的圆形按钮留白一致。
    static let tapAreaMargin: Double = 8

    /// 全屏默认跟随系统横屏安全区，正好避开屏幕圆角和灵动岛；
    /// 这里的 16 只是改成手动之前的占位值。
    static func defaults(for mode: Mode) -> Values {
        switch mode {
        case .fullScreen: Values(horizontalInset: 16, topInset: 4, bottomInset: 4, spacing: 16, followsSafeArea: true)
        case .inline: Values(horizontalInset: 8, topInset: 0, bottomInset: 0, spacing: 16)
        }
    }

    /// 存储值的范围。下限 `-tapAreaMargin` 时点按区域有一部分在边缘外，玻璃正好贴着边缘。
    static func horizontalInsetRange(for mode: Mode) -> ClosedRange<Double> {
        mode == .fullScreen ? -tapAreaMargin...100 : -tapAreaMargin...40
    }

    static let verticalInsetRange: ClosedRange<Double> = -tapAreaMargin...40
    /// 间距本来就按看得见的部分计算，不需要换算。
    static let spacingRange: ClosedRange<Double> = 8...28

    /// 全屏实际使用的左右边距：跟随系统时取系统安全区，至少 16pt。
    static func fullScreenHorizontalInset(_ values: Values, safeArea: CGFloat) -> CGFloat {
        values.followsSafeArea
            ? max(16, safeArea)
            : CGFloat(clamp(values.horizontalInset, to: horizontalInsetRange(for: .fullScreen)))
    }

    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : range.lowerBound
    }
}

/// 两组控件位置的当前值，设置页和播放器控件共用这一个对象。
///
/// 读写都经过这里：滑条改的是它，控件读的也是它，Observation 只让读到的控件重算。
/// 键名沿用 `PlayerChromeSettings.keys(for:)`，已保存的值继续有效；
/// 只写入真正改动的那一项，没动过的项仍然跟随默认值。
@MainActor @Observable
final class PlayerChromePreferences {
    static let shared = PlayerChromePreferences()

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
