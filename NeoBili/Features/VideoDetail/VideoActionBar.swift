import SwiftUI

/// 操作栏的排版参数。只想微调界面时改这几个数字就行。
private enum VideoActionBarLayout {
    /// 圆和下方数字之间的距离。
    static let captionSpacing: CGFloat = 5
}

/// 视频页的操作栏：点赞、不喜欢、投币、收藏、分享。
///
/// 五项等分整行宽度，每项是一颗圆形按钮，数字写在圆下面。
/// 参考 Apple Music 专辑页的「随机播放 / 添加」：内容里的按钮不用玻璃，平时是浅灰填充，
/// 点亮后换成主题色实心。轻点执行；点赞和收藏按住 0.5 秒执行扩展操作。
///
/// 圆里只放图标：数字放进圆里会把它撑成胶囊，五颗并排也放不下。
/// 数字挪到圆下方之后，「不喜欢」也能把文字写全。
struct VideoActionBar: View {
    @Environment(\.appThemeColor) private var themeColor
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
    /// 按住点赞 0.5 秒＝一键三连。
    let onTriple: () -> Void
    let onDislike: () -> Void
    let onCoin: () -> Void
    let onFavorite: () -> Void
    /// 按住收藏 0.5 秒＝挑收藏夹；轻点执行收藏／取消。
    let onPickFavoriteFolder: () -> Void

    @State private var showsShare = false

    var body: some View {
        HStack(spacing: 0) {
            item(
                icon: "VideoActionLike",
                caption: likeCount.biliCountText,
                isActive: isLiked,
                label: isLiked ? String(localized: "取消点赞") : String(localized: "点赞"),
                hint: String(localized: "持续按住一键三连"),
                action: onLike,
                longPressAction: onTriple
            )

            // 点踩没有公开的计数，官方这里显示的也是文字而不是数字。
            item(
                icon: "VideoActionDislike",
                caption: String(localized: "不喜欢"),
                isActive: isDisliked,
                label: isDisliked ? String(localized: "取消不喜欢") : String(localized: "不喜欢"),
                action: onDislike
            )

            item(
                icon: "VideoActionCoin",
                caption: coinCount.biliCountText,
                isActive: isCoined,
                label: isCoined ? String(localized: "已投币") : String(localized: "投币"),
                action: onCoin
            )

            item(
                icon: "VideoActionFavorite",
                caption: favoriteCount.biliCountText,
                isActive: isFavorited,
                label: isFavorited ? String(localized: "取消收藏") : String(localized: "favorite.action", defaultValue: "收藏"),
                hint: String(localized: "持续按住选择收藏夹"),
                action: onFavorite,
                longPressAction: onPickFavoriteFolder
            )

            shareItem
        }
        .controlSize(.large)
        .sheet(isPresented: $showsShare) {
            if let shareURL { VideoActionShareSheet(url: shareURL) }
        }
    }

    private func item(
        icon: String, caption: String, isActive: Bool, label: String,
        hint: String? = nil, action: @escaping () -> Void,
        longPressAction: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: VideoActionBarLayout.captionSpacing) {
            VideoHoldButton(icon: icon,
                            isActive: isActive, label: label,
                            secondaryLabel: hint, action: action, secondaryAction: longPressAction)
                .tint(themeColor)
                .frame(width: 52, height: 52)
            captionText(caption)
        }
        .frame(maxWidth: .infinity)
    }

    private var shareItem: some View {
        item(icon: "VideoActionShare", caption: shareCount.biliCountText,
             isActive: false, label: String(localized: "分享"), action: { showsShare = true })
            .disabled(shareURL == nil)
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

/// 原生 UIKit 按钮：轻点执行，按下时的高亮由系统处理。
private struct VideoHoldButton: UIViewRepresentable {
    let icon: String
    let isActive: Bool
    let label: String
    let secondaryLabel: String?
    let action: () -> Void
    let secondaryAction: (() -> Void)?
    @Environment(\.isEnabled) private var isEnabled

    func makeUIView(context: Context) -> HoldButton { HoldButton() }

    func updateUIView(_ button: HoldButton, context: Context) {
        // 系统按钮样式：平时是系统灰色按钮，点亮后换成跟随主题色（tintColor）的实心按钮。
        var config: UIButton.Configuration = isActive ? .filled() : .gray()
        config.baseForegroundColor = isActive ? .white : .label
        config.image = UIImage(named: icon)
        config.cornerStyle = .capsule
        config.contentInsets = .zero
        button.configuration = config
        button.isEnabled = isEnabled
        button.accessibilityLabel = label
        button.accessibilityHint = secondaryLabel
        button.primary = action
        button.secondary = secondaryAction
        button.accessibilityCustomActions = secondaryLabel.map {
            [UIAccessibilityCustomAction(name: $0, target: button, selector: #selector(HoldButton.accessibleSecondary))]
        }
    }
}

/// 轻点走按钮自己的点击事件。有扩展操作时再挂一个长按手势：按住 0.5 秒执行扩展操作，
/// 手势识别的同时系统会取消按钮这一次的触摸，松手时不会再算一次轻点。
private final class HoldButton: UIButton, UIGestureRecognizerDelegate {
    static let holdDuration: TimeInterval = 0.5

    var primary: (() -> Void)?
    var secondary: (() -> Void)? {
        didSet {
            let enabled = secondary != nil
            if hold.isEnabled != enabled { hold.isEnabled = enabled }
        }
    }
    private let hold = UILongPressGestureRecognizer()

    init() {
        super.init(frame: .zero)
        addAction(UIAction { [weak self] _ in self?.primary?() }, for: .primaryActionTriggered)
        hold.addTarget(self, action: #selector(held(_:)))
        hold.minimumPressDuration = Self.holdDuration
        hold.allowableMovement = 10
        hold.delegate = self
        hold.isEnabled = false
        addGestureRecognizer(hold)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var isScrolling: Bool {
        var ancestor = superview
        while let view = ancestor {
            if let scroll = view as? UIScrollView, scroll.isDragging { return true }
            ancestor = view.superview
        }
        return false
    }

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, isEnabled, !isScrolling, let secondary else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        secondary()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        otherGestureRecognizer is UIPanGestureRecognizer
    }

    override func accessibilityActivate() -> Bool {
        guard isEnabled else { return false }
        primary?()
        return true
    }
    @objc func accessibleSecondary() -> Bool {
        guard isEnabled, let secondary else { return false }
        secondary()
        return true
    }
}

private struct VideoActionShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview("操作栏") {
    VideoActionBar(likeCount: 1329, coinCount: 68, favoriteCount: 273, shareCount: 28,
                   isLiked: true, isDisliked: false, isCoined: false, isFavorited: true,
                   shareURL: URL(string: "https://www.bilibili.com"),
                   onLike: {}, onTriple: {}, onDislike: {}, onCoin: {}, onFavorite: {}, onPickFavoriteFolder: {})
        .padding()
}
