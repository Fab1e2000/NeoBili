import SwiftUI
import UIKit
import MediaPlayer
import AVFAudio

/// 方向确认后锁定操作，使用增量位移，避免识别成功时突然跳变。
/// 参考 PiliPlus 3e6ac82 的 _onPanUpdate；控件仍位于此层上方。
struct PlayerVerticalGestureLayer: View {
    let isFullScreen: Bool
    let currentTime: Double
    let duration: Double
    var canSeek = true
    var canLongPress = false
    var feedbackTopInset: CGFloat = 0
    var onDoubleTap: () -> Void = {}
    var onLongPressChanged: (Bool) -> Void = { _ in }
    let onTap: () -> Void
    let onToggleFullScreen: () -> Void
    let onSeekChanged: (Double) -> Void
    let onSeekEnded: (Double) -> Void
    let onSeekCancelled: () -> Void
    @AppStorage(PlayerGestureSettings.leftKey) private var left = 0.33
    @AppStorage(PlayerGestureSettings.rightKey) private var right = 0.67
    @AppStorage(PlayerGestureSettings.reverseKey) private var reversed = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var output = PlayerGestureOutput()
    @State private var zone: Zone?
    @State private var value: CGFloat = 0
    @State private var lastTranslation: CGSize = .zero
    @State private var direction: CGFloat = 1
    @State private var fired = false
    @State private var beganFullscreen = false
    @State private var seek: PlayerSeekGestureState?
    @State private var lastVolumeUpdate: TimeInterval = 0
    @State private var isLongPressActive = false

    private enum Zone { case brightness, volume, fullscreen, seek }

    var body: some View {
        GeometryReader { geometry in
            PlayerGestureInput(
                canLongPress: canLongPress,
                onTap: onTap,
                onDoubleTap: { if canSeek { onDoubleTap() } },
                onLongPressChanged: { active in
                    if active {
                        isLongPressActive = true
                        onLongPressChanged(true)
                    } else {
                        endLongPress()
                    }
                },
                onDrag: { drag, ended in
                    update(drag, size: geometry.size)
                    if ended { finish(cancelled: false) }
                },
                onCancel: { finish(cancelled: true) }
            )
                .overlay(alignment: .top) {
                    feedback
                        .environment(\.colorScheme, .dark)
                        .padding(.top, max(feedbackTopInset, geometry.safeAreaInsets.top)
                                 + min(max(geometry.size.height * 0.06, 8), 24))
                        .padding(.horizontal, 12)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .background {
                    PlayerGestureOutputView(output: output)
                        .frame(width: 1, height: 1)
                        .clipped()
                        .opacity(0.001)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        }
        .onChange(of: canLongPress) { _, enabled in if !enabled { endLongPress() } }
        .onChange(of: canSeek) { _, enabled in if !enabled { finish(cancelled: true) } }
        .onChange(of: isFullScreen) { finish(cancelled: true) }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { finish(cancelled: true) }
        }
        .onDisappear { finish(cancelled: true) }
    }

    @ViewBuilder
    private var feedback: some View {
        if isLongPressActive {
            Label("2×", systemImage: "forward.fill")
                .font(.callout.monospacedDigit())
                .padding(12)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
        } else if let seek, zone == .seek {
            VStack(spacing: 6) {
                Label(seek.isCancelled ? "松开取消跳转" : (seek.delta >= 0 ? "快进" : "后退"),
                      systemImage: seek.isCancelled ? "xmark" : (seek.delta >= 0 ? "forward.fill" : "backward.fill"))
                Text("\(PlaybackTime.text(seek.target)) / \(PlaybackTime.text(seek.duration))")
                    .font(.headline.monospacedDigit())
                Text(seek.isCancelled ? String(localized: "移回画面继续调整") : String(localized: "\(seek.delta >= 0 ? "+" : "−")\(Int(abs(seek.delta).rounded())) 秒 · 松开跳转"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .padding(12)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
        } else if zone == .brightness || zone == .volume {
            Label("\(Int((value * 100).rounded()))%", systemImage: zone == .brightness ? "sun.max.fill" : "speaker.wave.2.fill")
                .font(.callout.monospacedDigit())
                .padding(12)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func update(_ drag: PlayerGestureDrag, size: CGSize) {
        if zone == nil {
            let dx = abs(drag.translation.width)
            let dy = abs(drag.translation.height)
            guard max(dx, dy) >= 18 else { return }
            if dx > 2 * dy {
                guard canSeek, let state = PlayerSeekGestureState(
                    position: currentTime, duration: duration, width: size.width,
                    translation: drag.translation.width
                ) else { return }
                seek = state
                zone = .seek
                onSeekChanged(state.target)
            } else if dy > 2 * dx {
                let bounds = PlayerGestureSettings.boundaries(left: left, right: right)
                let x = drag.startLocation.x / max(size.width, 1)
                zone = x < bounds.0 ? .brightness : (x > bounds.1 ? .volume : .fullscreen)
                value = zone == .brightness ? output.brightness : output.volume
                if zone == .volume { output.beginVolumeGesture() }
            } else {
                return
            }
            direction = reversed ? -1 : 1
            beganFullscreen = isFullScreen
            fired = false
            lastTranslation = drag.translation
            lastVolumeUpdate = 0
            return
        }

        let dy = (drag.translation.height - lastTranslation.height) * direction
        lastTranslation = drag.translation
        switch zone {
        case .seek:
            seek?.update(translation: drag.translation.width, location: drag.location, height: size.height)
            if let seek { onSeekChanged(seek.target) }
        case .brightness:
            value = min(max(value - dy / max(size.height * 3, 1), 0), 1)
            output.setBrightness(value)
        case .volume:
            value = min(max(value - dy / max(size.height * 0.5, 1), 0), 1)
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastVolumeUpdate >= 0.02 {
                output.setVolume(value)
                lastVolumeUpdate = now
            }
        case .fullscreen:
            let cumulativeDy = drag.translation.height * direction
            guard !fired, abs(cumulativeDy) > 2.5 else { return }
            fired = true
            if beganFullscreen ? cumulativeDy > 0 : cumulativeDy < 0 {
                onToggleFullScreen()
            }
        case nil: break
        }
    }

    private func endLongPress() {
        guard isLongPressActive else { return }
        isLongPressActive = false
        onLongPressChanged(false)
    }

    private func finish(cancelled: Bool) {
        endLongPress()
        let completedZone = zone
        zone = nil
        fired = false
        if completedZone == .volume { output.setVolume(value) }
        output.endVolumeGesture()
        if completedZone == .seek, let seek {
            if cancelled || seek.isCancelled { onSeekCancelled() }
            else { onSeekEnded(seek.target) }
        }
        seek = nil
    }
}

/// The ordinary host supplies the scene for brightness. A volume view is only
/// in the window while a volume gesture owns the feedback; idle hardware keys
/// therefore use the system HUD.
@MainActor
final class PlayerGestureOutput {
    weak var view: UIView?
    private var volumeView: MPVolumeView?

    var brightness: CGFloat { view?.window?.windowScene?.screen.brightness ?? 0.5 }
    var volume: CGFloat { CGFloat(AVAudioSession.sharedInstance().outputVolume) }
    func setBrightness(_ value: CGFloat) { view?.window?.windowScene?.screen.brightness = value }

    func beginVolumeGesture() {
        guard volumeView == nil, let view, view.window != nil else { return }
        let control = MPVolumeView(frame: view.bounds)
        control.isUserInteractionEnabled = false
        control.accessibilityElementsHidden = true
        view.addSubview(control)
        volumeView = control
    }

    func setVolume(_ value: CGFloat) {
        guard let slider = volumeView?.subviews.compactMap({ $0 as? UISlider }).first else { return }
        slider.setValue(Float(value), animated: false)
        slider.sendActions(for: .valueChanged)
    }

    func endVolumeGesture() {
        volumeView?.removeFromSuperview()
        volumeView = nil
    }
}

struct PlayerGestureOutputView: UIViewRepresentable {
    let output: PlayerGestureOutput
    func makeCoordinator() -> PlayerGestureOutput { output }
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        output.view = view
        return view
    }
    func updateUIView(_ view: UIView, context: Context) { output.view = view }
    static func dismantleUIView(_ view: UIView, coordinator: PlayerGestureOutput) {
        coordinator.endVolumeGesture()
        coordinator.view = nil
    }
}
