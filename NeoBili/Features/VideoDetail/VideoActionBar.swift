import SwiftUI

/// 操作栏的排版参数。只想微调界面时改这几个数字就行。
private enum VideoActionBarLayout {
    /// 圆里那个图标的字号。
    static let iconSize: CGFloat = 19
    /// 图标的画布。它加上按钮样式自带的内边距决定圆的直径。
    static let iconBox: CGFloat = 26
    /// 圆和下方数字之间的距离。
    static let captionSpacing: CGFloat = 5
}

/// 视频页的操作栏：点赞、不喜欢、投币、收藏、分享。
///
/// 五项等分整行宽度，每项是一颗圆形的 Liquid Glass 按钮，数字写在圆下面。
/// 激活状态换成 `.glassProminent` 加 tint——高亮由系统样式负责，不再自己
/// 涂前景色，深浅色和按下态都跟着系统走。
///
/// 圆里只放图标：数字放进圆里会把它撑成胶囊，五颗并排也放不下。
/// 数字挪到圆下方之后，「不喜欢」也能把文字写全。
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
        .controlSize(.large)
    }

    /// 激活与否走两种不同的按钮样式，所以要分支——`buttonStyle` 的类型不同，
    /// 没法用一个三目表达式带过。
    @ViewBuilder
    private func styled(_ button: some View, isActive: Bool) -> some View {
        if isActive {
            button.buttonStyle(.glassProminent).tint(.accentColor)
        } else {
            button.buttonStyle(.glass)
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
        VStack(spacing: VideoActionBarLayout.captionSpacing) {
            styled(
                ActionItemButton(action: action, longPressAction: longPressAction) {
                    icon(symbol, isActive: isActive)
                },
                isActive: isActive
            )
            .buttonBorderShape(.circle)

            captionText(caption)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityHint(hint ?? "")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        // 长按是隐藏操作，给辅助技术留一个显式入口。
        .accessibilityAction(named: Text(hint ?? "")) {
            longPressAction?()
        }
    }

    private var shareItem: some View {
        VStack(spacing: VideoActionBarLayout.captionSpacing) {
            Group {
                if let shareURL {
                    ShareLink(item: shareURL) {
                        icon("arrowshape.turn.up.right", isActive: false)
                    }
                } else {
                    // 详情还没回来时保留占位，五项形状和间距不会先后不一。
                    Button {} label: { icon("arrowshape.turn.up.right", isActive: false) }
                        .disabled(true)
                }
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)

            captionText(shareCount.biliCountText)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("分享")
    }

    private func icon(_ symbol: String, isActive: Bool) -> some View {
        // 直接给出空心/实心两个符号名，而不是靠 `.symbolVariant` 去改变体。
        // 变体修饰符会沿着视图树往下传，容易和外层的样式互相影响；配合
        // `.contentTransition(.symbolEffect(.replace))` 时符号还可能停在
        // 上一帧的形态上——激活状态看起来时灵时不灵就是这么来的。
        //
        // 前景色交给按钮样式：激活态是 glassProminent 的反色，未激活是玻璃上的
        // 默认标签色，自己涂反而会和系统样式打架。
        Image(systemName: isActive ? "\(symbol).fill" : symbol)
            .font(.system(size: VideoActionBarLayout.iconSize))
            .frame(width: VideoActionBarLayout.iconBox, height: VideoActionBarLayout.iconBox)
    }

    private func captionText(_ caption: String) -> some View {
        Text(caption)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            // 位数多的时候宁可缩一点，也别把这一列撑宽。
            .minimumScaleFactor(0.75)
    }
}

/// 操作栏上的一颗按钮：短按走 `action`，长按走 `longPressAction`，**两者互斥**。
///
/// 要点在于 `simultaneousGesture` 的语义是两个手势**都**成立：长按满 0.45 秒
/// 触发一次长按之后，手指抬起时按钮的点击照样还会再触发一次。表现出来就是
/// 一键三连（长按点赞）之后紧跟着一次普通点赞，把三连刚点上的赞又取消掉了。
///
/// 样式由调用方用 `buttonStyle` 从外面套（玻璃胶囊），这里不指定。
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
