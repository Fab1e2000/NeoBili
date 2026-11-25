import NeoBiliDomain
import SwiftUI

/// 投屏进行中覆盖在播放器区域的控制层：支持播放/暂停、进度拖动（点播与离线缓存）、音量调节、画质/音质热切换、换设备与退出投屏。
struct CastPlaybackOverlay: View {
    let castSession: CastSessionModel
    let isFullScreen: Bool
    var safeAreaInsets = EdgeInsets()
    var videoQualityControl: PlayerQualityControl? = nil
    var hiResControl: PlayerHiResControl? = nil
    var hasEpisodes = false
    var supportsPlaybackMode = true
    let onBack: () -> Void
    let onSwitchDevice: () -> Void
    let onExitCast: () -> Void

    @Environment(\.playbackModePreferences) private var modePreferences
    @State private var scrubPosition: TimeInterval = 0

    private var supportsSeeking: Bool {
        castSession.activeMedia?.kind.supportsSeeking == true && castSession.duration > 0
    }

    private var statusText: String {
        if castSession.isSwitchingStream {
            return String(localized: "正在切换清晰度…")
        }
        switch castSession.phase {
        case .idle:
            return ""
        case .connecting:
            return String(localized: "正在连接投屏设备…")
        case .casting:
            switch castSession.transportState {
            case .playing: return String(localized: "正在投屏播放")
            case .paused: return String(localized: "投屏已暂停")
            case .transitioning: return String(localized: "设备缓冲中…")
            case .stopped: return String(localized: "投屏播放已停止")
            case .unknown: return String(localized: "已连接投屏设备")
            }
        case .error(let message):
            return message
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let isCompactHeight = !isFullScreen && geometry.size.height < 280
            let horizontalInset = isFullScreen ? max(16, max(safeAreaInsets.leading, safeAreaInsets.trailing) + 8) : 12
            let topInset = isFullScreen ? max(12, safeAreaInsets.top + 6) : 8
            let bottomInset = isFullScreen ? max(12, safeAreaInsets.bottom + 8) : 8

            ZStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.9), Color(white: 0.12).opacity(0.95)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(spacing: isCompactHeight ? 6 : 12) {
                    topBar(compact: isCompactHeight)

                    Spacer(minLength: 0)

                    deviceHeader(compact: isCompactHeight)

                    transportControls(compact: isCompactHeight)

                    if let controlError = castSession.controlError, !isErrorPhase {
                        Text(controlError)
                            .font(.app(.caption2))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    bottomBar(compact: isCompactHeight)
                }
                .padding(.horizontal, horizontalInset)
                .padding(.top, topInset)
                .padding(.bottom, bottomInset)
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .clipped()
        }
        .environment(\.colorScheme, .dark)
        .accessibilityIdentifier("player.castOverlay")
    }

    @ViewBuilder
    private func topBar(compact: Bool) -> some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                PlayerGlassCircleLabel(
                    symbol: "chevron.left",
                    diameter: compact ? 30 : 34,
                    symbolSize: compact ? 14 : 16,
                    hitDiameter: compact ? 36 : 44
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFullScreen ? "退出全屏" : "返回")

            if let hiResControl {
                hiResButton(hiResControl, compact: compact)
            }

            if let videoQualityControl {
                qualityMenu(videoQualityControl, compact: compact, identifier: "cast.videoQuality")
            }

            if supportsPlaybackMode {
                playbackModeMenu(compact: compact)
            }

            Spacer(minLength: 4)

            Button {
                onSwitchDevice()
            } label: {
                if compact {
                    PlayerGlassCircleLabel(
                        symbol: "tv.badge.wifi",
                        diameter: 30,
                        symbolSize: 13,
                        hitDiameter: 34
                    )
                } else {
                    Label("切换设备", systemImage: "tv.badge.wifi")
                        .font(.app(.caption))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.16), in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("切换投屏设备")

            Button {
                onExitCast()
            } label: {
                Text("退出投屏")
                    .font(.app(compact ? .caption2 : .caption))
                    .foregroundStyle(.white)
                    .padding(.horizontal, compact ? 9 : 11)
                    .padding(.vertical, compact ? 5 : 6)
                    .background(.red.opacity(0.76), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(height: compact ? 34 : 44)
    }

    @ViewBuilder
    private func hiResButton(_ control: PlayerHiResControl, compact: Bool) -> some View {
        Button(action: control.onToggle) {
            Text(control.title)
                .font(.app(compact ? .caption2 : .caption, weight: .semibold))
                .foregroundStyle(control.isActive ? Color.white : Color.white.opacity(0.45))
                .lineLimit(1)
                .padding(.horizontal, compact ? 8 : 10)
                .padding(.vertical, compact ? 5 : 6)
                .background(.white.opacity(control.isActive ? 0.24 : 0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!control.isEnabled || castSession.isSwitchingStream || castSession.phase == .connecting)
        .accessibilityLabel(control.isActive ? "关闭 Hi-Res 音质" : "开启 Hi-Res 音质")
        .accessibilityIdentifier("cast.audioQuality")
    }

    @ViewBuilder
    private func playbackModeMenu(compact: Bool) -> some View {
        let autoTitle = PlaybackModeSettings.autoAdvanceTitle(hasEpisodes: hasEpisodes)
        let currentTitle: String = modePreferences.loopEnabled
            ? String(localized: "洗脑循环")
            : (modePreferences.autoAdvanceEnabled ? autoTitle : String(localized: "播完暂停"))
        Menu {
            Button {
                modePreferences.toggleLoop()
            } label: {
                if modePreferences.loopEnabled {
                    Label("洗脑循环", systemImage: "checkmark")
                } else {
                    Text("洗脑循环")
                }
            }
            Divider()
            Button {
                modePreferences.setAutoAdvanceEnabled(true)
            } label: {
                if modePreferences.autoAdvanceEnabled {
                    Label(autoTitle, systemImage: "checkmark")
                } else {
                    Text(autoTitle)
                }
            }
            Button {
                modePreferences.setAutoAdvanceEnabled(false)
            } label: {
                if !modePreferences.autoAdvanceEnabled {
                    Label("播完暂停", systemImage: "checkmark")
                } else {
                    Text("播完暂停")
                }
            }
        } label: {
            Text(currentTitle)
                .font(.app(compact ? .caption2 : .caption, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, compact ? 8 : 10)
                .padding(.vertical, compact ? 5 : 6)
                .background(.white.opacity(0.16), in: Capsule())
        }
        .accessibilityLabel("播放模式")
        .accessibilityValue(currentTitle)
        .accessibilityIdentifier("cast.mode")
    }

    @ViewBuilder
    private func qualityMenu(_ control: PlayerQualityControl, compact: Bool, identifier: String) -> some View {
        Menu {
            ForEach(control.options) { option in
                Button {
                    control.onSelect(option.id)
                } label: {
                    if option.id == control.selectedID {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            Text(control.title)
                .font(.app(compact ? .caption2 : .caption, weight: .semibold))
                .foregroundStyle(.white.opacity(control.isEnabled ? 1 : 0.55))
                .lineLimit(1)
                .padding(.horizontal, compact ? 8 : 10)
                .padding(.vertical, compact ? 5 : 6)
                .background(.white.opacity(0.16), in: Capsule())
        }
        .disabled(!control.isEnabled || castSession.isSwitchingStream || castSession.phase == .connecting)
        .accessibilityLabel(control.accessibilityLabel)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private func deviceHeader(compact: Bool) -> some View {
        VStack(spacing: compact ? 3 : 6) {
            if !compact {
                Image(systemName: "tv.badge.wifi")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }
            HStack(spacing: 6) {
                if compact {
                    Image(systemName: "tv.badge.wifi")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(castSession.activeDevice?.name ?? String(localized: "投屏设备"))
                    .font(.app(compact ? .subheadline : .headline))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Text(statusText)
                .font(.app(compact ? .caption2 : .caption))
                .foregroundStyle(isErrorPhase ? Color.orange : Color.white.opacity(0.74))
                .lineLimit(compact ? 1 : 2)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func transportControls(compact: Bool) -> some View {
        let playDiameter: CGFloat = compact ? 42 : 52
        let volDiameter: CGFloat = compact ? 32 : 38
        HStack(spacing: compact ? 18 : 24) {
            if castSession.activeDevice?.renderingControlURL != nil {
                Button {
                    Task { await castSession.adjustVolume(by: -5) }
                } label: {
                    PlayerGlassCircleLabel(
                        symbol: "speaker.minus.fill",
                        diameter: volDiameter,
                        symbolSize: compact ? 13 : 16,
                        hitDiameter: volDiameter
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("降低音量")
            }

            Button {
                Task { await castSession.togglePlayPause() }
            } label: {
                if castSession.phase == .connecting || castSession.isSwitchingStream {
                    ProgressView()
                        .tint(.white)
                        .frame(width: playDiameter, height: playDiameter)
                        .background(.white.opacity(0.15), in: Circle())
                } else {
                    PlayerGlassCircleLabel(
                        symbol: castSession.transportState.isPlaying ? "pause.fill" : "play.fill",
                        diameter: playDiameter,
                        symbolSize: compact ? 19 : 24,
                        hitDiameter: playDiameter
                    )
                }
            }
            .buttonStyle(.plain)
            .disabled(castSession.phase != .casting || castSession.isSwitchingStream)
            .accessibilityLabel(castSession.transportState.isPlaying ? "暂停投屏" : "继续投屏")

            if castSession.activeDevice?.renderingControlURL != nil {
                Button {
                    Task { await castSession.adjustVolume(by: 5) }
                } label: {
                    PlayerGlassCircleLabel(
                        symbol: "speaker.plus.fill",
                        diameter: volDiameter,
                        symbolSize: compact ? 13 : 16,
                        hitDiameter: volDiameter
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("增大音量")
            }
        }
    }

    @ViewBuilder
    private func bottomBar(compact: Bool) -> some View {
        if supportsSeeking {
            HStack(spacing: 8) {
                Text(formatClock(castSession.isScrubbing ? scrubPosition : castSession.currentTime))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(minWidth: 38, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { castSession.isScrubbing ? scrubPosition : castSession.currentTime },
                        set: { scrubPosition = $0 }
                    ),
                    in: 0...max(1, castSession.duration),
                    onEditingChanged: { editing in
                        castSession.isScrubbing = editing
                        if !editing {
                            let target = scrubPosition
                            Task { await castSession.seek(to: target) }
                        }
                    }
                )
                .controlSize(compact ? .mini : .regular)
                .tint(.white)

                Text(formatClock(castSession.duration))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(minWidth: 38, alignment: .trailing)
            }
            .frame(height: compact ? 24 : 32)
        } else if castSession.activeMedia?.kind == .live {
            Label("直播投屏中", systemImage: "dot.radiowaves.left.and.right")
                .font(.app(.caption2))
                .foregroundStyle(.white.opacity(0.8))
                .frame(height: 20)
        }
    }

    private var isErrorPhase: Bool {
        if case .error = castSession.phase { return true }
        return false
    }

    private func formatClock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
