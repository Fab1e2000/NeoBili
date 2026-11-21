#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI

/// 投屏进行中覆盖在播放器区域的控制层：支持播放/暂停、进度拖动（点播与离线缓存）、音量调节、换设备与退出投屏。
struct CastPlaybackOverlay: View {
    let castSession: CastSessionModel
    let isFullScreen: Bool
    var safeAreaInsets = EdgeInsets()
    let onBack: () -> Void
    let onSwitchDevice: () -> Void
    let onExitCast: () -> Void

    @State private var scrubPosition: TimeInterval = 0

    private var supportsSeeking: Bool {
        castSession.activeMedia?.kind.supportsSeeking == true && castSession.duration > 0
    }

    private var statusText: String {
        switch castSession.phase {
        case .idle:
            ""
        case .connecting:
            String(localized: "正在连接投屏设备…")
        case .casting:
            switch castSession.transportState {
            case .playing: String(localized: "正在投屏播放")
            case .paused: String(localized: "投屏已暂停")
            case .transitioning: String(localized: "设备缓冲中…")
            case .stopped: String(localized: "投屏播放已停止")
            case .unknown: String(localized: "已连接投屏设备")
            }
        case .error(let message):
            message
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black.opacity(0.92), Color(white: 0.12).opacity(0.96)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Button(action: onBack) {
                        PlayerGlassCircleLabel(symbol: "chevron.left", diameter: 32, symbolSize: 16, hitDiameter: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isFullScreen ? "退出全屏" : "返回")

                    Spacer()

                    Button("切换设备", systemImage: "tv.badge.wifi", action: onSwitchDevice)
                        .font(.app(.caption))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.14), in: Capsule())

                    Button("退出投屏", action: onExitCast)
                        .font(.app(.caption))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.red.opacity(0.72), in: Capsule())
                }

                Spacer(minLength: 4)

                VStack(spacing: 6) {
                    Image(systemName: "tv.badge.wifi")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(castSession.activeDevice?.name ?? String(localized: "投屏设备"))
                        .font(.app(.headline))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(statusText)
                        .font(.app(.caption))
                        .foregroundStyle(isErrorPhase ? Color.orange : Color.white.opacity(0.72))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 18) {
                    if castSession.activeDevice?.renderingControlURL != nil {
                        Button {
                            Task { await castSession.adjustVolume(by: -5) }
                        } label: {
                            PlayerGlassCircleLabel(symbol: "speaker.minus.fill", diameter: 36, symbolSize: 15, hitDiameter: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("降低音量")
                    }

                    Button {
                        Task { await castSession.togglePlayPause() }
                    } label: {
                        if castSession.phase == .connecting {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 48, height: 48)
                                .background(.white.opacity(0.15), in: Circle())
                        } else {
                            PlayerGlassCircleLabel(
                                symbol: castSession.transportState.isPlaying ? "pause.fill" : "play.fill",
                                diameter: 48,
                                symbolSize: 22
                            )
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(castSession.phase != .casting)
                    .accessibilityLabel(castSession.transportState.isPlaying ? "暂停投屏" : "继续投屏")

                    if castSession.activeDevice?.renderingControlURL != nil {
                        Button {
                            Task { await castSession.adjustVolume(by: 5) }
                        } label: {
                            PlayerGlassCircleLabel(symbol: "speaker.plus.fill", diameter: 36, symbolSize: 15, hitDiameter: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("增大音量")
                    }
                }

                if let controlError = castSession.controlError, !isErrorPhase {
                    Text(controlError)
                        .font(.app(.caption2))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if supportsSeeking {
                    HStack(spacing: 8) {
                        Text(formatClock(castSession.isScrubbing ? scrubPosition : castSession.currentTime))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(minWidth: 44, alignment: .leading)

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
                        .tint(.white)

                        Text(formatClock(castSession.duration))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                } else if castSession.activeMedia?.kind == .live {
                    Label("直播投屏中", systemImage: "dot.radiowaves.left.and.right")
                        .font(.app(.caption))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, max(14, safeAreaInsets.leading + 8))
            .padding(.top, max(10, isFullScreen ? safeAreaInsets.top + 8 : 10))
            .padding(.bottom, max(10, isFullScreen ? safeAreaInsets.bottom + 8 : 10))
        }
        .environment(\.colorScheme, .dark)
        .accessibilityIdentifier("player.castOverlay")
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
