import SwiftUI
import UIKit

extension View {
    /// 播放器控件压在视频上，统一用透明变体（`.clear`），让画面透出来。
    ///
    /// 透明变体自己不保证对比度，靠控件层里的调暗层（`PlayerChromeScrim`）把下面的画面压暗；
    /// Apple 要求两种变体不混用，所以控件层里的玻璃都走这里或 `.clear`。
    func playerGlassSurface<S: Shape>(in shape: S) -> some View {
        glassEffect(.clear, in: shape)
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
            .font(.system(size: symbolSize, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .glassEffect(.clear.interactive(), in: Circle())
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
    /// 控件位置设置，全屏横屏与非全屏各一组。
    private var chromePreferences: PlayerChromePreferences { .shared }

    var body: some View {
        // 边距和间距来自设置页（PlayerChromePreferences）。在 body 里读取，
        // 设置变化时由这一层重算，不依赖 GeometryReader 闭包里的依赖追踪。
        let fullScreenValues = chromePreferences.fullScreen
        let inlineValues = chromePreferences.inline
        GeometryReader { geometry in
            // 横屏全屏：控件铺到视频两侧黑边上，左右默认跟随系统横屏安全区，正好避开屏幕圆角和
            // 灵动岛；上下默认各 4pt，右上角与右下角的按钮到边缘一样远。
            // 其余（视频页上的小窗、竖屏全屏）：在安全区内再按设置留边。
            // 边距可以是负数（最小 -8）：点按区域有一截在边缘外，看得见的玻璃正好贴边。
            let usesScreenEdges = isFullScreen && geometry.size.width > geometry.size.height
            let vertical = PlayerChromeSettings.verticalInsetRange
            let inlineSide = CGFloat(PlayerChromeSettings.clamp(inlineValues.horizontalInset,
                                                                to: PlayerChromeSettings.horizontalInsetRange(for: .inline)))
            let leading = usesScreenEdges
                ? PlayerChromeSettings.fullScreenHorizontalInset(fullScreenValues, safeArea: safeAreaInsets.leading)
                : safeAreaInsets.leading + inlineSide
            let trailing = usesScreenEdges
                ? PlayerChromeSettings.fullScreenHorizontalInset(fullScreenValues, safeArea: safeAreaInsets.trailing)
                : safeAreaInsets.trailing + inlineSide
            let top = usesScreenEdges
                // 玻璃不进顶部安全区；横屏时顶部安全区是 0，玻璃可以贴到屏幕上缘。
                ? max(CGFloat(PlayerChromeSettings.clamp(fullScreenValues.topInset, to: vertical)),
                      safeAreaInsets.top - CGFloat(PlayerChromeSettings.tapAreaMargin))
                : safeAreaInsets.top + CGFloat(PlayerChromeSettings.clamp(inlineValues.topInset, to: vertical))
            let bottom = usesScreenEdges
                ? CGFloat(PlayerChromeSettings.clamp(fullScreenValues.bottomInset, to: vertical))
                : safeAreaInsets.bottom + CGFloat(PlayerChromeSettings.clamp(inlineValues.bottomInset, to: vertical))
            let bounds = CGRect(x: leading, y: top,
                                width: max(0, geometry.size.width - leading - trailing),
                                height: max(0, geometry.size.height - top - bottom))
            let layout = PlayerChromeLayout(bounds: bounds, textScale: textScale, isFullScreen: isFullScreen,
                                            hasVideoQuality: videoQualityControl != nil,
                                            hasAudioQuality: audioQualityControl != nil,
                                            hasDanmaku: showsDanmakuToggle && onToggleDanmaku != nil,
                                            hasSendDanmaku: onSendDanmaku != nil && !hasError,
                                            videoQualityWidth: preferredWidth(videoQualityControl),
                                            audioQualityWidth: preferredWidth(audioQualityControl),
                                            spacing: CGFloat(PlayerChromeSettings.clamp(
                                                usesScreenEdges ? fullScreenValues.spacing : inlineValues.spacing,
                                                to: PlayerChromeSettings.spacingRange)))
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
                                .glassEffect(.clear.interactive(), in: Circle())
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
            // 调暗层在玻璃下面、弹幕上面（控件层本身盖在弹幕上），跟控件一起出现和隐藏。
            .background {
                PlayerChromeScrim(layout: layout, size: geometry.size,
                                  errorControls: hasError ? errorStateControls(layout) : nil)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    /// 出错时仍然显示的控件：返回、更多、弹幕开关和全屏。
    private func errorStateControls(_ layout: PlayerChromeLayout) -> [CGRect] {
        let danmaku = showsDanmakuToggle && onToggleDanmaku != nil ? layout.danmaku : .zero
        return [layout.back, layout.more, danmaku, layout.fullScreen].filter { !$0.isEmpty }
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
        return canControlPlayback ? String(localized: "缓冲中，\(action)") : (isLive ? String(localized: "直播正在加载") : String(localized: "视频正在加载"))
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
        // 胶囊按文字宽度画，在标题区里靠左，紧跟返回按钮，间距与其它控件一致。
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 48)
        .allowsHitTesting(false)
        .accessibilityIdentifier("player.metadata")
    }

    private var secondaryActions: some View {
        HStack(spacing: 12) {
            if !isFullScreen, let onToggleCompact {
                Button(action: onToggleCompact) {
                    Label(isCompact ? "展开" : "收起", systemImage: compactSymbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .glassEffect(.clear.interactive(), in: Capsule())
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(compactTitle)
                .accessibilityIdentifier("player.compact")
            }
            Spacer(minLength: 0)
        }
        .buttonStyle(.plain)
    }

    private var compactTitle: String { isCompact ? String(localized: "展开视频画面") : String(localized: "收起视频画面") }
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
                .glassEffect(.clear, in: Capsule())
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

/// 透明玻璃下面的调暗层。
///
/// 透明变体本身不压暗画面，白色图标和文字遇到白墙、雪地这类亮画面会看不清：
/// - 平时：整个画面轻压一层，上下两排控件后面各加一段渐变，中间的播放按钮后面再压一小片。
/// - 出错时：错误提示和重试按钮在控件层下面，不能跟着变暗，只在仍然显示的几个按钮背后各压一小圈。
///
/// 控件自动隐藏后调暗层也跟着消失，平时观看不受影响。
private struct PlayerChromeScrim: View {
    let layout: PlayerChromeLayout
    let size: CGSize
    /// 出错时仍然显示的控件；为 nil 表示正常状态。
    let errorControls: [CGRect]?

    /// 整个画面的基础调暗。
    private static let baseOpacity = 0.15
    /// 渐变贴着画面上下边缘处的浓度，往画面中间逐渐变淡。
    private static let edgeOpacity = 0.5
    /// 渐变越过控件行后再延伸的距离，让过渡更柔和。
    private static let fadeExtent: CGFloat = 28
    /// 单个控件背后那一小片调暗的中心浓度。
    private static let spotOpacity = 0.35

    var body: some View {
        Group {
            if let errorControls {
                ZStack {
                    ForEach(Array(errorControls.enumerated()), id: \.offset) { _, rect in
                        spot(behind: rect)
                    }
                }
            } else {
                normalScrim
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var normalScrim: some View {
        let rows = rowExtents
        return ZStack {
            Color.black.opacity(Self.baseOpacity)
            if let top = rows.top {
                edgeGradient(from: .top)
                    .frame(height: min(size.height, top + Self.fadeExtent))
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            if let bottom = rows.bottom {
                edgeGradient(from: .bottom)
                    .frame(height: min(size.height, size.height - bottom + Self.fadeExtent))
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            if !layout.transport.isEmpty {
                spot(behind: layout.transport)
            }
        }
    }

    /// 从画面边缘往里淡出；中段放缓，控件所在的那一截保持较深。
    private func edgeGradient(from edge: UnitPoint) -> some View {
        let opacity = Self.edgeOpacity
        return LinearGradient(stops: [
            .init(color: .black.opacity(opacity), location: 0),
            .init(color: .black.opacity(opacity * 0.8), location: 0.4),
            .init(color: .black.opacity(opacity * 0.35), location: 0.75),
            .init(color: .black.opacity(0), location: 1)
        ], startPoint: edge, endPoint: edge == .top ? .bottom : .top)
    }

    /// 以控件中心为圆心的一小片柔和调暗，边缘淡到透明。
    private func spot(behind rect: CGRect) -> some View {
        let radius = max(rect.width, rect.height) * 1.1
        return RadialGradient(colors: [.black.opacity(Self.spotOpacity), .black.opacity(0)],
                              center: .center, startRadius: 0, endRadius: radius)
            .frame(width: radius * 2, height: radius * 2)
            .position(x: rect.midX, y: rect.midY)
    }

    /// 上排控件最靠下的边、下排控件最靠上的边；中间的播放按钮不算在内。
    private var rowExtents: (top: CGFloat?, bottom: CGFloat?) {
        let controls = [layout.back, layout.more, layout.metadata, layout.danmaku,
                        layout.videoQuality, layout.audioQuality,
                        layout.timeline, layout.fullScreen, layout.sendDanmaku, layout.secondaryActions]
            .filter { !$0.isEmpty }
        let middle = size.height / 2
        return (controls.filter { $0.midY < middle }.map(\.maxY).max(),
                controls.filter { $0.midY >= middle }.map(\.minY).min())
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

#Preview("播放器控件 · 非全屏") {
    PlayerGlassChrome(
        title: "示例视频标题",
        videoQualityControl: PlayerQualityControl(title: "1080P", accessibilityLabel: "分辨率", options: [],
                                                 selectedID: 0, isEnabled: true, onSelect: { _ in }),
        audioQualityControl: PlayerQualityControl(title: "192K", accessibilityLabel: "音质", options: [],
                                                 selectedID: 0, isEnabled: true, onSelect: { _ in }),
        position: 83, duration: 300, buffered: 120, isPlaying: true,
        isDanmakuEnabled: true, showsDanmakuToggle: true, onToggleDanmaku: {}
    ) { EmptyView() }
    .frame(height: 230)
    .background(.indigo.gradient)
}

#Preview("播放器控件 · 全屏", traits: .landscapeLeft) {
    PlayerGlassChrome(
        title: "示例视频标题",
        videoQualityControl: PlayerQualityControl(title: "1080P", accessibilityLabel: "分辨率", options: [],
                                                 selectedID: 0, isEnabled: true, onSelect: { _ in }),
        audioQualityControl: PlayerQualityControl(title: "192K", accessibilityLabel: "音质", options: [],
                                                 selectedID: 0, isEnabled: true, onSelect: { _ in }),
        position: 83, duration: 300, buffered: 120, isPlaying: false, isFullScreen: true,
        safeAreaInsets: EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59),
        isDanmakuEnabled: true, showsDanmakuToggle: true, onToggleDanmaku: {}, onSendDanmaku: {}
    ) { EmptyView() }
    .background(.indigo.gradient)
    .ignoresSafeArea()
}
