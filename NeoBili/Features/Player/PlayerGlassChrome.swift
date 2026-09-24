import SwiftUI
import UIKit

extension View {
    /// 视频背景会明暗变化，控制层统一使用深色系统玻璃以保持白色符号的对比。
    func playerGlassSurface<S: Shape>(in shape: S) -> some View {
        glassEffect(.regular, in: shape)
            .environment(\.colorScheme, .dark)
    }
}

/// 圆形玻璃只是外观，完整矩形点击区域保留到最后，边角也能接收触摸。
struct PlayerGlassCircleLabel: View {
    let symbol: String
    var diameter: CGFloat = 44
    var symbolSize: CGFloat = 20
    var hitDiameter: CGFloat?

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: symbolSize, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .glassEffect(.regular.interactive(), in: Circle())
            .frame(width: hitDiameter ?? diameter, height: hitDiameter ?? diameter)
            .contentShape(Rectangle())
            .environment(\.colorScheme, .dark)
    }
}

struct PlayerQualityControl {
    struct Option: Identifiable {
        let id: Int
        let title: String
    }
    let title: String
    let accessibilityLabel: String
    let options: [Option]
    let selectedID: Int
    let isEnabled: Bool
    let onSelect: (Int) -> Void
}

/// 弹幕开关的「弹」字圆角徽标。SF Symbols 里没有贴近 B 站弹幕语义的符号，
/// 自绘这个徽标与玻璃圆钮的视觉分量一致；关闭时整块降透明度。
struct DanmakuBadge: View {
    var isEnabled: Bool

    var body: some View {
        Text("弹")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(isEnabled ? Color.white : Color.white.opacity(0.4))
            .frame(width: 19, height: 21)
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(isEnabled ? Color.white : Color.white.opacity(0.4), lineWidth: 1.6)
            }
    }
}

/// 玻璃控制层只接收值与动作，便于在真机上独立检查每种画幅，不加载播放内核。
struct PlayerGlassChrome<MenuContent: View>: View {
    var title = ""
    var subtitle = ""
    var shareURL: URL?
    var videoQualityControl: PlayerQualityControl?
    var audioQualityControl: PlayerQualityControl?
    var position: Double = 0
    var duration: Double = 0
    var buffered: Double = 0
    var progressSource: PlayerProgressSource?
    var isPlaying = false
    var canControlPlayback = true
    var isWaiting = false
    var isLive = false
    var isFullScreen = false
    var isCompact = false
    var hasError = false
    var safeAreaInsets = EdgeInsets()
    var isDanmakuEnabled = false
    var showsDanmakuToggle = false
    var onToggleDanmaku: (() -> Void)?
    var onBack: () -> Void = {}
    var onTogglePlayback: () -> Void = {}
    var onToggleFullScreen: () -> Void = {}
    /// 全屏时显示「发弹幕」按钮。
    var onSendDanmaku: (() -> Void)?
    var onToggleCompact: (() -> Void)?
    var onScrub: (Double) -> Void = { _ in }
    var onScrubEnd: (Double) -> Void = { _ in }
    var onMenuInteraction: () -> Void = {}
    @ViewBuilder var menuContent: () -> MenuContent
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            // 横屏全屏：控件铺到视频两侧黑边上，左右按系统安全区收进来——系统给的横屏安全区
            // 正好避开屏幕圆角和灵动岛，上下两行按钮不会伸进四角的圆弧里。
            let usesScreenEdges = isFullScreen && geometry.size.width > geometry.size.height
            let leading = usesScreenEdges ? max(16, safeAreaInsets.leading) : safeAreaInsets.leading + 8
            let trailing = usesScreenEdges ? max(16, safeAreaInsets.trailing) : safeAreaInsets.trailing + 8
            let top = usesScreenEdges ? max(4, safeAreaInsets.top) : safeAreaInsets.top
            // 上下两行离屏幕边缘的距离保持一致：底部不再让出主屏幕指示条的整段安全区，
            // 右上角与右下角的按钮到边缘一样远。
            let bottom = usesScreenEdges ? top : safeAreaInsets.bottom
            let bounds = CGRect(x: leading, y: top,
                                width: max(0, geometry.size.width - leading - trailing),
                                height: max(0, geometry.size.height - top - bottom))
            let layout = PlayerChromeLayout(bounds: bounds, textScale: textScale, isFullScreen: isFullScreen,
                                            hasVideoQuality: videoQualityControl != nil,
                                            hasAudioQuality: audioQualityControl != nil,
                                            hasDanmaku: showsDanmakuToggle && onToggleDanmaku != nil,
                                            hasSendDanmaku: onSendDanmaku != nil && !hasError,
                                            videoQualityWidth: preferredWidth(videoQualityControl),
                                            audioQualityWidth: preferredWidth(audioQualityControl))
            GlassEffectContainer(spacing: 6) {
                ZStack {
                    if !layout.back.isEmpty { backButton.chromeFrame(layout.back) }
                    if !layout.more.isEmpty {
                        settingsMenu(inlineQualities: !layout.videoQuality.isEmpty || !layout.audioQuality.isEmpty,
                                     needsPlaybackAction: layout.transport.isEmpty)
                            .chromeFrame(layout.more)
                    }
                    fullScreenButton.chromeFrame(layout.fullScreen)
                    if let onSendDanmaku, !layout.sendDanmaku.isEmpty {
                        Button(action: onSendDanmaku) {
                            PlayerGlassCircleLabel(symbol: "text.bubble", diameter: 32, symbolSize: 15, hitDiameter: 48)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("发弹幕")
                        .accessibilityIdentifier("player.sendDanmaku")
                        .chromeFrame(layout.sendDanmaku)
                    }
                    if showsDanmakuToggle, let onToggleDanmaku, layout.danmaku != .zero {
                        Button(action: onToggleDanmaku) {
                            DanmakuBadge(isEnabled: isDanmakuEnabled)
                                .frame(width: 32, height: 32)
                                .glassEffect(.regular.interactive(), in: Circle())
                                .frame(width: 48, height: 48)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isDanmakuEnabled ? "关闭弹幕" : "开启弹幕")
                        .accessibilityIdentifier("player.danmaku")
                        .chromeFrame(layout.danmaku)
                    }
                    if !hasError, let videoQualityControl, !layout.videoQuality.isEmpty {
                        qualityMenu(videoQualityControl, identifier: "player.videoQuality")
                            .chromeFrame(layout.videoQuality)
                    }
                    if !hasError, let audioQualityControl, !layout.audioQuality.isEmpty {
                        qualityMenu(audioQualityControl, identifier: "player.audioQuality")
                            .chromeFrame(layout.audioQuality)
                    }
                    if !hasError {
                        if !layout.metadata.isEmpty, !title.isEmpty {
                            metadata.chromeFrame(layout.metadata)
                        }
                        if !layout.transport.isEmpty && (canControlPlayback || isWaiting) {
                            Button(action: onTogglePlayback) {
                                if isWaiting {
                                    ProgressView().tint(.white)
                                        .frame(width: layout.transport.width, height: layout.transport.height)
                                        .playerGlassSurface(in: Circle())
                                        .contentShape(Rectangle())
                                } else {
                                    PlayerGlassCircleLabel(symbol: isPlaying ? "pause.fill" : "play.fill",
                                                           diameter: layout.transport.width,
                                                           symbolSize: layout.mode == .expanded ? 30 : 24)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(!canControlPlayback)
                            .accessibilityLabel(transportTitle)
                            .accessibilityIdentifier("player.transport")
                            .chromeFrame(layout.transport)
                        }
                        PlayerTimeline(
                            progressSource: progressSource ?? PlayerProgressSource {
                                .init(position: position, duration: duration, buffered: buffered)
                            },
                            isLive: isLive, isWaiting: isWaiting, canControlPlayback: canControlPlayback,
                            showsTimeLabels: layout.showsTimeLabels, isMinimal: layout.mode == .minimal,
                            onScrub: onScrub, onScrubEnd: onScrubEnd
                        )
                        .chromeFrame(layout.timeline)
                        if !layout.secondaryActions.isEmpty {
                            secondaryActions
                                .chromeFrame(layout.secondaryActions)
                        }
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private func preferredWidth(_ control: PlayerQualityControl?) -> CGFloat? {
        guard let control else { return nil }
        // 控制层可见时 body 以帧率重算；字体测量结果只取决于 (标题, 字号档位)，
        // 记忆化后同帧不再重复测。
        let memoKey = "\(control.title)|\(control.options.count)|\(textScale)" as NSString
        if let memo = PlayerGlassWidthMemo.cache.object(forKey: memoKey) { return CGFloat(memo.doubleValue) }
        let font = UIFont.systemFont(ofSize: 12 * textScale, weight: .semibold)
        let width = max(48, ceil((control.title as NSString).size(withAttributes: [.font: font]).width) + 24)
        PlayerGlassWidthMemo.cache.setObject(NSNumber(value: width), forKey: memoKey)
        return width
    }

    private var transportTitle: String {
        let action = isPlaying ? "暂停" : "播放"
        guard isWaiting else { return action }
        return canControlPlayback ? "缓冲中，\(action)" : (isLive ? "直播正在加载" : "视频正在加载")
    }

    private var backButton: some View {
        Button(action: onBack) { PlayerGlassCircleLabel(symbol: "chevron.left", diameter: 32, symbolSize: 16, hitDiameter: 48) }
            .buttonStyle(.plain)
            .accessibilityLabel(isFullScreen ? "退出全屏" : "返回")
            .accessibilityIdentifier("player.back")
    }

    private var fullScreenButton: some View {
        Button(action: onToggleFullScreen) {
            PlayerGlassCircleLabel(symbol: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                                   diameter: 32, symbolSize: 16, hitDiameter: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFullScreen ? "退出全屏" : "进入全屏")
        .accessibilityIdentifier("player.fullscreen")
    }

    private var metadata: some View {
        VStack(spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 16)
        .frame(height: 32)
        .playerGlassSurface(in: Capsule())
        .frame(height: 48)
        .allowsHitTesting(false)
        .accessibilityIdentifier("player.metadata")
    }

    private var secondaryActions: some View {
        HStack(spacing: 12) {
            if !isFullScreen, let onToggleCompact {
                Button(action: onToggleCompact) {
                    Label(isCompact ? "展开" : "收起", systemImage: compactSymbol)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .glassEffect(.regular.interactive(), in: Capsule())
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(compactTitle)
                .accessibilityIdentifier("player.compact")
            }
            Spacer(minLength: 0)
        }
        .buttonStyle(.plain)
    }

    private var compactTitle: String { isCompact ? "展开视频画面" : "收起视频画面" }
    private var compactSymbol: String { isCompact ? "chevron.compact.up" : "chevron.compact.down" }

    private func settingsMenu(inlineQualities: Bool, needsPlaybackAction: Bool) -> some View {
        ZStack {
        Menu {
            if needsPlaybackAction {
                Button(isPlaying ? "暂停" : "播放", systemImage: isPlaying ? "pause.fill" : "play.fill", action: onTogglePlayback)
                    .disabled(!canControlPlayback)
            }
            // 极矮画幅装不下第二排；展开全屏即可使用独立画质、音质按钮。
            if !inlineQualities {
                if let videoQualityControl { Menu(videoQualityControl.accessibilityLabel) { qualityOptions(videoQualityControl) } }
                if let audioQualityControl { Menu(audioQualityControl.accessibilityLabel) { qualityOptions(audioQualityControl) } }
            }
            menuContent()
            if !hasError, !isFullScreen, let onToggleCompact {
                Divider()
                Button(compactTitle, systemImage: compactSymbol) {
                    onToggleCompact()
                    onMenuInteraction()
                }
            }
        } label: {
            Color.clear.frame(width: 48, height: 48).contentShape(Rectangle())
        }
        .buttonStyle(PlayerMenuButtonStyle(onPress: onMenuInteraction))
        .accessibilityLabel("更多播放选项")
        .accessibilityIdentifier("player.more")
            PlayerGlassCircleLabel(symbol: "ellipsis", diameter: 32, symbolSize: 16, hitDiameter: 48)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    private func qualityMenu(_ control: PlayerQualityControl, identifier: String) -> some View {
        ZStack {
        Menu { qualityOptions(control) } label: {
            Color.clear.frame(maxWidth: .infinity).frame(height: 48).contentShape(Rectangle())
        }
        .buttonStyle(PlayerMenuButtonStyle(onPress: onMenuInteraction))
        .menuIndicator(.hidden)
        .disabled(!control.isEnabled)
        .accessibilityLabel(control.accessibilityLabel)
        .accessibilityValue(control.title)
        .accessibilityIdentifier(identifier)
            Text(control.title)
                .font(.system(size: 12 * textScale, weight: .semibold))
                .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity).frame(height: 32)
                .glassEffect(.regular, in: Capsule())
                .opacity(control.isEnabled ? 1 : 0.4)
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    @ViewBuilder private func qualityOptions(_ control: PlayerQualityControl) -> some View {
        ForEach(control.options) { option in
            Button { control.onSelect(option.id) } label: {
                if option.id == control.selectedID { Label(option.title, systemImage: "checkmark") }
                else { Text(option.title) }
            }
            .disabled(!control.isEnabled)
        }
    }
}

private struct PlayerMenuButtonStyle: ButtonStyle {
    let onPress: () -> Void
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { onPress() }
            }
    }
}

/// PlayerGlassChrome 是泛型类型放不下静态存储属性；字体测量的记忆化挂在这里。
@MainActor
private enum PlayerGlassWidthMemo {
    static let cache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 64
        return cache
    }()
}

private extension View {
    func chromeFrame(_ rect: CGRect) -> some View {
        frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
    }
}
