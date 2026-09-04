import SwiftUI

/// 屏幕左缘的「触控死区」。
enum LeftEdgeTapDeadZone {
    /// 与设置页共用的存储键。
    static let storageKey = "neobili.edgeDeadZoneWidth"

    /// 默认宽度，和系统边缘手势的感应范围（约 20pt）同量级、略小一点，
    /// 尽量少挡住卡片本身。
    static let defaultWidth: Double = 16

    /// 设置页滑杆允许的最大宽度。
    static let maxWidth: Double = 100
}

extension View {
    /// 给页面内容盖上左缘触控死区：这一小条竖条里的点击不生效。
    ///
    /// 从左缘往右滑返回时，手指落下的那一瞬间容易被下面的卡片当成一次
    /// 点击，视频就被误打开了。这层竖条把左缘一小段内的触摸拦在这里、
    /// 不再往下传，误触点击因此无效。
    ///
    /// 滑动返回不受影响：系统的边缘滑动手势挂在导航容器上，导航容器的
    /// 手势识别器照常收到它内部（含这片死区）的所有触摸，识别成功后
    /// 反过来取消这里挂的点击手势，返回照常进行。
    ///
    /// 代价：在这条里**起手**的竖向滚动也滚不动列表（触摸同样被拦住），
    /// 这是死区的固有行为，所以默认只有 16pt，宽度可在设置页调整、
    /// 调成 0 等于关闭。
    ///
    /// 要挂在导航栈的内容上（页面根部的 `Group` / `ScrollView` 等）。挂到
    /// 根视图 `TabView` 外面是不行的：那样死区脱离了导航容器，边缘手势
    /// 反而收不到这里的触摸，滑动返回会被整个弄坏。
    func leftEdgeTapDeadZone() -> some View {
        modifier(LeftEdgeTapDeadZoneModifier())
    }
}

private struct LeftEdgeTapDeadZoneModifier: ViewModifier {
    /// 宽度跟着设置页那根滑杆走，拖完立刻全局生效。
    @AppStorage(LeftEdgeTapDeadZone.storageKey) private var width = LeftEdgeTapDeadZone.defaultWidth

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .leading) {
                // 0 表示关闭，一条都不盖。`Color.clear` 本身不参与命中测试；
                // `.contentShape` 再挂一个空的点击手势，这一条才算「可交互」，
                // 触摸才会停在这里不再传给下面的卡片。
                if width >= 1 {
                    Color.clear
                        .frame(width: width)
                        .contentShape(Rectangle())
                        .onTapGesture {}
                }
            }
    }
}
