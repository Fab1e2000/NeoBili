import SwiftUI

/// 屏幕左缘的「触控死区」。
enum LeftEdgeTapDeadZone {
    /// 与设置页共用的存储键。
    static let storageKey = "neobili.edgeDeadZoneWidth"

    /// 默认宽度，比系统边缘手势的感应范围（约 20pt）略宽，
    /// 侧滑返回时更不容易误点到卡片。
    static let defaultWidth: Double = 30

    /// 设置页滑杆允许的最大宽度。
    static let maxWidth: Double = 100
}

extension View {
    /// 拦截左缘区域内的点击及从该区域开始的竖向滚动，宽度为 0 时关闭。
    /// 挂在导航栈内容内，让祖先导航容器仍能接收系统边缘返回手势。
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
