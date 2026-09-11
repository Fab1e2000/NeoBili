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
    var isPlaying = false
    var canControlPlayback = true
    var isWaiting = false
    var isLive = false
    var isFullScreen = false
    var isCompact = false
    var hasError = false
    var safeAreaInsets = EdgeInsets()
    var onBack: () -> Void = {}
    var onTogglePlayback: () -> Void = {}
    var onToggleFullScreen: () -> Void = {}
    var onToggleCompact: (() -> Void)?
    var onScrub: (Double) -> Void = { _ in }
    var onScrubEnd: (Double) -> Void = { _ in }
    var onMenuInteraction: () -> Void = {}
    @ViewBuilder var menuContent: () -> MenuContent
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            // 横屏刘海位于侧边中段，上下按钮行只避让圆角；使用整个屏幕，包括视频两侧黑边。
            let usesScreenEdges = isFullScreen && geometry.size.width > geometry.size.height
            let leading = usesScreenEdges ? 28 : safeAreaInsets.leading + 16
            let trailing = usesScreenEdges ? 28 : safeAreaInsets.trailing + 16
            let top = usesScreenEdges ? max(12, safeAreaInsets.top + 6) : safeAreaInsets.top + 6
            let bounds = CGRect(x: leading, y: top,
                                width: max(0, geometry.size.width - leading - trailing),
                                height: max(0, geometry.size.height - top - safeAreaInsets.bottom - 8))
            let layout = PlayerChromeLayout(bounds: bounds, textScale: textScale, isFullScreen: isFullScreen,
                                            hasVideoQuality: videoQualityControl != nil,
                                            hasAudioQuality: audioQualityControl != nil,
                                            videoQualityWidth: preferredWidth(videoQualityControl),
                                            audioQualityWidth: preferredWidth(audioQualityControl))
            GlassEffectContainer(spacing: 6) {
                ZStack {
                    backButton.chromeFrame(layout.back)
                    settingsMenu(inlineQualities: !layout.videoQuality.isEmpty || !layout.audioQuality.isEmpty)
                        .chromeFrame(layout.more)
                    fullScreenButton.chromeFrame(layout.fullScreen)
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
                        if canControlPlayback || isWaiting {
                            Button(action: onTogglePlayback) {
                                if isWaiting {
                                    ProgressView().tint(.white)
                                        .frame(width: layout.transport.width, height: layout.transport.height)
                                        .playerGlassSurface(in: Circle())
                                        .contentShape(Rectangle())
                                } else {
                                    PlayerGlassCircleLabel(symbol: isPlaying ? "pause.fill" : "play.fill",
                                                           diameter: layout.transport.width,
                                                           symbolSize: layout.mode == .expanded ? 40 : (layout.mode == .inline ? 27 : 20))
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(!canControlPlayback)
                            .accessibilityLabel(transportTitle)
                            .accessibilityIdentifier("player.transport")
                            .chromeFrame(layout.transport)
                        }
                        timeline(showsTimeLabels: layout.showsTimeLabels, isMinimal: layout.mode == .minimal)
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
        let font = UIFont.systemFont(ofSize: 12 * textScale, weight: .semibold)
        return max(48, ceil((control.title as NSString).size(withAttributes: [.font: font]).width) + 24)
    }

    private var transportTitle: String {
        let action = isPlaying ? "暂停" : "播放"
        guard isWaiting else { return action }
        return canControlPlayback ? "缓冲中，\(action)" : (isLive ? "直播正在加载" : "视频正在加载")
    }

    private var backButton: some View {
        Button(action: onBack) { PlayerGlassCircleLabel(symbol: "chevron.left", hitDiameter: 48) }
            .buttonStyle(.plain)
            .accessibilityLabel(isFullScreen ? "退出全屏" : "返回")
            .accessibilityIdentifier("player.back")
    }

    private var fullScreenButton: some View {
        Button(action: onToggleFullScreen) {
            PlayerGlassCircleLabel(symbol: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                                   hitDiameter: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFullScreen ? "退出全屏" : "进入全屏")
        .accessibilityIdentifier("player.fullscreen")
    }

    private var metadata: some View {
        VStack(spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            if !subtitle.isEmpty {
                Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.7))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
        .playerGlassSurface(in: Capsule())
        .allowsHitTesting(false)
        .accessibilityIdentifier("player.metadata")
    }

    @ViewBuilder
    private func timeline(showsTimeLabels: Bool, isMinimal: Bool) -> some View {
        if isLive {
            HStack(spacing: 6) {
                Circle().fill(isWaiting ? Color.white.opacity(0.6) : .red).frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(isWaiting ? (isMinimal ? "连接" : "连接中") : (isMinimal ? "直播" : "直播中"))
                    .font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, isMinimal ? 6 : 12)
            .frame(height: 48)
            .playerGlassSurface(in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(isWaiting ? "正在连接直播" : "直播中")
            .accessibilityIdentifier("player.liveStatus")
        } else {
            HStack(spacing: showsTimeLabels ? 8 : 0) {
                if showsTimeLabels {
                    Text(PlaybackTime.text(position)).lineLimit(1).minimumScaleFactor(0.7).accessibilityHidden(true)
                }
                VideoScrubber(position: position, buffered: buffered, duration: duration,
                              onScrub: onScrub, onScrubEnd: onScrubEnd)
                    .disabled(!canControlPlayback || duration <= 0)
                    .frame(minWidth: 44)
                if showsTimeLabels {
                    Text(PlaybackTime.text(duration))
                        .foregroundStyle(.white.opacity(0.8)).accessibilityHidden(true)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, showsTimeLabels ? 12 : 6)
            .frame(maxHeight: .infinity)
            .playerGlassSurface(in: Capsule())
            .accessibilityIdentifier("player.timeline")
        }
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

    private func settingsMenu(inlineQualities: Bool) -> some View {
        Menu {
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
        } label: { PlayerGlassCircleLabel(symbol: "ellipsis", hitDiameter: 48) }
        .buttonStyle(PlayerMenuButtonStyle(onPress: onMenuInteraction))
        .accessibilityLabel("更多播放选项")
        .accessibilityIdentifier("player.more")
    }

    private func qualityMenu(_ control: PlayerQualityControl, identifier: String) -> some View {
        Menu { qualityOptions(control) } label: {
            Text(control.title)
                .font(.system(size: 12 * textScale, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
                .glassEffect(.regular.interactive(), in: Capsule())
                .contentShape(Rectangle())
        }
        .buttonStyle(PlayerMenuButtonStyle(onPress: onMenuInteraction))
        .menuIndicator(.hidden)
        .disabled(!control.isEnabled)
        .accessibilityLabel(control.accessibilityLabel)
        .accessibilityValue(control.title)
        .accessibilityIdentifier(identifier)
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

/// 直接观察原生按钮按下状态，不在 Menu 上叠加竞争点击的 Tap/Drag 手势。
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

private extension View {
    func chromeFrame(_ rect: CGRect) -> some View {
        frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
    }
}
