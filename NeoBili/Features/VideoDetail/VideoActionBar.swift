import SwiftUI

/// 视频页的操作栏：点赞、不喜欢、投币、收藏、分享。
///
/// 五项等分整行宽度，图标在上、文字在下——这是官方客户端的排法，也是 iOS 上
/// 一排同级操作的常见形态。激活状态只靠颜色和实心图标区分，不额外加背景，
/// 免得五个色块把简介区压得很重。
struct VideoActionBar: View {
    let likeCount: Int
    let coinCount: Int
    let favoriteCount: Int
    let shareCount: Int

    let isLiked: Bool
    let isDisliked: Bool
    let isCoined: Bool
    let isFavorited: Bool

    /// 分享用系统面板，所以这里只需要一个可分享的链接。
    let shareURL: URL?

    let onLike: () -> Void
    /// 长按点赞＝一键三连。
    let onTriple: () -> Void
    let onDislike: () -> Void
    let onCoin: () -> Void
    let onFavorite: () -> Void
    /// 长按收藏＝挑收藏夹（已收藏时短按是直接取消，所以改收藏夹要走长按）。
    let onPickFavoriteFolder: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            item(
                symbol: "hand.thumbsup",
                caption: likeCount.biliCountText,
                isActive: isLiked,
                label: isLiked ? "取消点赞" : "点赞",
                hint: "长按一键三连",
                action: onLike,
                longPressAction: onTriple
            )

            // 点踩没有公开的计数，官方这里显示的也是文字而不是数字。
            item(
                symbol: "hand.thumbsdown",
                caption: "不喜欢",
                isActive: isDisliked,
                label: isDisliked ? "取消不喜欢" : "不喜欢",
                action: onDislike
            )

            item(
                symbol: "bitcoinsign.circle",
                caption: coinCount.biliCountText,
                isActive: isCoined,
                label: isCoined ? "已投币" : "投币",
                action: onCoin
            )

            item(
                symbol: "star",
                caption: favoriteCount.biliCountText,
                isActive: isFavorited,
                label: isFavorited ? "取消收藏" : "收藏",
                hint: "长按选择收藏夹",
                action: onFavorite,
                longPressAction: onPickFavoriteFolder
            )

            shareItem
        }
    }

    private func item(
        symbol: String,
        caption: String,
        isActive: Bool,
        label: String,
        hint: String? = nil,
        action: @escaping () -> Void,
        longPressAction: (() -> Void)? = nil
    ) -> some View {
        ActionItemButton(action: action, longPressAction: longPressAction) {
            content(symbol: symbol, caption: caption, isActive: isActive)
        }
        .accessibilityLabel(label)
        .accessibilityHint(hint ?? "")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        // 长按是隐藏操作，给辅助技术留一个显式入口。
        .accessibilityAction(named: Text(hint ?? "")) {
            longPressAction?()
        }
    }

    @ViewBuilder
    private var shareItem: some View {
        let label = content(symbol: "arrowshape.turn.up.right", caption: shareCount.biliCountText, isActive: false)

        if let shareURL {
            ShareLink(item: shareURL) { label }
                .buttonStyle(.plain)
                .accessibilityLabel("分享")
        } else {
            // 详情还没回来时保留占位，五项间距不会先窄后宽地跳一下。
            label.opacity(0.4)
        }
    }

    private func content(symbol: String, caption: String, isActive: Bool) -> some View {
        VStack(spacing: 4) {
            // 直接给出空心/实心两个符号名，而不是靠 `.symbolVariant` 去改变体。
            // 变体修饰符会沿着视图树往下传，容易和外层的样式互相影响；配合
            // `.contentTransition(.symbolEffect(.replace))` 时符号还可能停在
            // 上一帧的形态上——激活状态看起来时灵时不灵就是这么来的。
            Image(systemName: isActive ? "\(symbol).fill" : symbol)
                .font(.system(size: 22))

            Text(caption)
                .font(.caption2)
                .lineLimit(1)
        }
        .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondary))
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

/// 操作栏上的一颗按钮：短按走 `action`，长按走 `longPressAction`，**两者互斥**。
///
/// 要点在于 `simultaneousGesture` 的语义是两个手势**都**成立：长按满 0.45 秒
/// 触发一次长按之后，手指抬起时按钮的点击照样还会再触发一次。表现出来就是
/// 一键三连（长按点赞）之后紧跟着一次普通点赞，把三连刚点上的赞又取消掉了。
///
/// 按钮本身仍然是 `Button`——换成裸的 `TapGesture` / `ExclusiveGesture` 之后，
/// 点击要等长按先判定失败才轮得到，在 ScrollView 里经常直接被吞掉。这里保留
/// Button 的点击，改用一个标记把长按之后那次多余的点击挡掉：
/// 按下瞬间复位，长按成立时置位，抬手时按钮先看标记再决定要不要执行。
private struct ActionItemButton<Label: View>: View {
    let action: () -> Void
    let longPressAction: (() -> Void)?
    @ViewBuilder var label: Label

    /// 这一次按压是否已经走了长按。抬手时的点击靠它判断该不该跳过。
    @State private var didLongPress = false

    var body: some View {
        Button {
            // 长按刚跑过，这次抬手不再算一次点击。
            // 标记不在这里清：手指划出按钮再抬起时这段根本不会执行，
            // 留给下一次按下的 onChanged 复位才不会漏。
            guard !didLongPress else { return }
            action()
        } label: {
            label
        }
        .buttonStyle(.plain)
        .simultaneousGesture(longPressGesture)
    }

    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.45)
            // 手指落下就复位，所以标记不会跨越两次按压残留。
            .onChanged { _ in didLongPress = false }
            .onEnded { _ in
                guard let longPressAction else { return }
                didLongPress = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                longPressAction()
            }
    }
}
