import SwiftUI

/// 列表里移除一张卡片的动效参数。
///
/// 要的观感是「卡片先消失，下方的卡片再替位」，所以拆成两段**顺序**执行：
/// 1. 卡片原地淡出，列表纹丝不动（`cardFadeOut`）；
/// 2. 淡出完成后才把条目从数据源移走，空位收拢、下方卡片上移补位。
///
/// 原来一段 `withAnimation { items.remove }` 同时做淡出和上移，淡出还没走完
/// 下方卡片就压了上来，两张卡片叠在一起，看起来不连贯。
enum CardRemovalAnimation {
    /// 删除入口是长按菜单，菜单退场时系统会在卡片上盖一层快照。不先等它
    /// 掀开，淡出就发生在快照后面，用户看到的是卡片静止一阵后瞬间消失。
    /// 250ms 实测不够（新式菜单退场更慢），先用 500ms。
    static let menuDismissWaitMilliseconds: UInt64 = 500
    /// 第一段：卡片原地淡出。
    static let fade: Animation = .easeOut(duration: 0.28)
    /// 第一段的时长（毫秒）。等它走完再收拢空位。
    static let fadeMilliseconds: UInt64 = 300
    /// 第二段：收拢空位，下方卡片上移补位。
    ///
    /// 用带一点点回弹的弹簧而不是固定曲线：补位的卡片轻轻落定，
    /// 比匀速滑动更有「卡进了位置」的感觉。
    static let collapse: Animation = .spring(duration: 0.4, bounce: 0.12)
    /// 第二段走完后延迟多久清理「正在移除」标记（毫秒）。标记要活过退出
    /// 转场，否则同一条目的残影会在半途重新显形。
    static let collapseMilliseconds: UInt64 = 450
}

extension View {
    /// 移除动效的第一段：卡片原地淡出、占位不变，所以列表此时完全不动。
    ///
    /// 淡出完成后再由调用方把条目从数据源移走；那张已经在退出转场里的
    /// 卡片带着这里的透明度离开，不会重新显形。
    ///
    /// 动画绑在视图上（`.animation(value:)`）而不是只靠调用方的
    /// `withAnimation`：长按菜单退场附近的事务经常被系统吞掉，
    /// 事务驱动的动画会直接跳到终态。
    func cardFadeOut(isRemoving: Bool) -> some View {
        opacity(isRemoving ? 0 : 1)
            .animation(CardRemovalAnimation.fade, value: isRemoving)
    }
}
