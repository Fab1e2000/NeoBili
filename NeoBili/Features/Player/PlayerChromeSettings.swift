import CoreGraphics

/// 播放器控件的位置设置：全屏横屏与非全屏（视频页上的小窗、竖屏全屏）各一组，
/// 设置页可调，`PlayerGlassChrome` 实时读取。
enum PlayerChromeSettings {
    enum Mode: String, CaseIterable, Identifiable {
        case fullScreen, inline

        var id: String { rawValue }
        var title: String { self == .fullScreen ? "全屏" : "非全屏" }
    }

    struct Keys {
        let horizontalInset: String
        let topInset: String
        let bottomInset: String
        let spacing: String
    }

    struct Values {
        let horizontalInset: Double
        let topInset: Double
        let bottomInset: Double
        let spacing: Double
    }

    /// 全屏的键沿用最早只有全屏设置时的名字，已保存的值继续有效。
    static func keys(for mode: Mode) -> Keys {
        switch mode {
        case .fullScreen:
            Keys(horizontalInset: "neobili.fullScreenChrome.horizontalInset",
                 topInset: "neobili.fullScreenChrome.topInset",
                 bottomInset: "neobili.fullScreenChrome.bottomInset",
                 spacing: "neobili.fullScreenChrome.spacing")
        case .inline:
            Keys(horizontalInset: "neobili.inlineChrome.horizontalInset",
                 topInset: "neobili.inlineChrome.topInset",
                 bottomInset: "neobili.inlineChrome.bottomInset",
                 spacing: "neobili.inlineChrome.spacing")
        }
    }

    /// 负数的左右边距表示跟随系统横屏安全区（只用于全屏：正好避开屏幕圆角和灵动岛）。
    static let automaticHorizontalInset: Double = -1

    static func defaults(for mode: Mode) -> Values {
        switch mode {
        case .fullScreen: Values(horizontalInset: automaticHorizontalInset, topInset: 4, bottomInset: 4, spacing: 16)
        case .inline: Values(horizontalInset: 8, topInset: 0, bottomInset: 0, spacing: 16)
        }
    }

    static func horizontalInsetRange(for mode: Mode) -> ClosedRange<Double> {
        mode == .fullScreen ? 16...100 : 0...40
    }

    static let verticalInsetRange: ClosedRange<Double> = 0...40
    static let spacingRange: ClosedRange<Double> = 8...28

    /// 全屏实际使用的左右边距：自动时取系统安全区，至少 16pt。
    static func fullScreenHorizontalInset(stored: Double, safeArea: CGFloat) -> CGFloat {
        stored < 0 ? max(16, safeArea) : CGFloat(clamp(stored, to: horizontalInsetRange(for: .fullScreen)))
    }

    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : range.lowerBound
    }
}
