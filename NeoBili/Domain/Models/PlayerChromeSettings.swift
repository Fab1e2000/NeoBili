import CoreGraphics
import Foundation

/// 播放器控件的位置设置：全屏横屏与非全屏（视频页上的小窗、竖屏全屏）各一组，
/// 设置页可调，`PlayerGlassChrome` 实时读取。当前值由 `PlayerChromePreferences` 保存。
public enum PlayerChromeSettings {
    public enum Mode: String, CaseIterable, Identifiable {
        case fullScreen, inline

        public var id: String { rawValue }
        public var title: String { self == .fullScreen ? String(localized: "全屏") : String(localized: "非全屏") }
    }

    public struct Keys {
        public let horizontalInset: String
        public let topInset: String
        public let bottomInset: String
        public let spacing: String
        /// 只有全屏有：左右边距是否跟随系统横屏安全区。
        public let followsSafeArea: String?
    }

    /// 边距存的是点按区域到边缘的距离（沿用旧键）；设置页显示的是看得见的玻璃到边缘的距离，
    /// 两者相差 `tapAreaMargin`。
    public struct Values: Equatable {
        public var horizontalInset: Double
        public var topInset: Double
        public var bottomInset: Double
        public var spacing: Double
        /// 只用于全屏：左右边距跟随系统横屏安全区，此时 `horizontalInset` 不生效。
        public var followsSafeArea = false

        public init(
            horizontalInset: Double,
            topInset: Double,
            bottomInset: Double,
            spacing: Double,
            followsSafeArea: Bool = false
        ) {
            self.horizontalInset = horizontalInset
            self.topInset = topInset
            self.bottomInset = bottomInset
            self.spacing = spacing
            self.followsSafeArea = followsSafeArea
        }
    }

    /// 全屏的键沿用最早只有全屏设置时的名字，已保存的值继续有效。
    public static func keys(for mode: Mode) -> Keys {
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
    public static let tapAreaMargin: Double = 8

    /// 全屏默认跟随系统横屏安全区，正好避开屏幕圆角和灵动岛；
    /// 这里的 16 只是改成手动之前的占位值。
    public static func defaults(for mode: Mode) -> Values {
        switch mode {
        case .fullScreen: Values(horizontalInset: 16, topInset: 4, bottomInset: 4, spacing: 16, followsSafeArea: true)
        case .inline: Values(horizontalInset: 8, topInset: 0, bottomInset: 0, spacing: 16)
        }
    }

    /// 存储值的范围。下限 `-tapAreaMargin` 时点按区域有一部分在边缘外，玻璃正好贴着边缘。
    public static func horizontalInsetRange(for mode: Mode) -> ClosedRange<Double> {
        mode == .fullScreen ? -tapAreaMargin...100 : -tapAreaMargin...40
    }

    public static let verticalInsetRange: ClosedRange<Double> = -tapAreaMargin...40
    /// 间距本来就按看得见的部分计算，不需要换算。
    public static let spacingRange: ClosedRange<Double> = 8...28

    /// 全屏实际使用的左右边距：跟随系统时取系统安全区，至少 16pt。
    public static func fullScreenHorizontalInset(_ values: Values, safeArea: CGFloat) -> CGFloat {
        values.followsSafeArea
            ? max(16, safeArea)
            : CGFloat(clamp(values.horizontalInset, to: horizontalInsetRange(for: .fullScreen)))
    }

    public static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : range.lowerBound
    }
}

