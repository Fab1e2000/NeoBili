import CoreGraphics

/// 全屏（横屏）播放器控件的位置设置，设置页可调，播放器实时读取。
enum FullScreenChromeSettings {
    static let horizontalInsetKey = "neobili.fullScreenChrome.horizontalInset"
    static let topInsetKey = "neobili.fullScreenChrome.topInset"
    static let bottomInsetKey = "neobili.fullScreenChrome.bottomInset"
    static let spacingKey = "neobili.fullScreenChrome.spacing"

    /// 负数表示跟随系统横屏安全区（正好避开屏幕圆角和灵动岛）。
    static let automaticHorizontalInset: Double = -1
    static let defaultTopInset: Double = 4
    static let defaultBottomInset: Double = 4
    static let defaultSpacing: Double = 16

    static let horizontalInsetRange: ClosedRange<Double> = 16...100
    static let verticalInsetRange: ClosedRange<Double> = 0...40
    static let spacingRange: ClosedRange<Double> = 8...28

    /// 实际使用的左右边距：自动时取系统安全区，至少 16pt。
    static func horizontalInset(stored: Double, safeArea: CGFloat) -> CGFloat {
        stored < 0 ? max(16, safeArea) : CGFloat(clamp(stored, to: horizontalInsetRange))
    }

    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : range.lowerBound
    }
}
