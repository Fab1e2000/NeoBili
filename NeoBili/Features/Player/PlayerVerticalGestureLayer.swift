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
    let onTap: () -> Void
    let onToggleFullScreen: () -> Void
    let onSeekChanged: (Double) -> Void
    let onSeekEnded: (Double) -> Void
    let onSeekCancelled: () -> Void
    @AppStorage(PlayerGestureSettings.leftKey) private var left = 0.33
    @AppStorage(PlayerGestureSettings.rightKey) private var right = 0.67
    @AppStorage(PlayerGestureSettings.reverseKey) private var reversed = false
    @State private var output = PlayerGestureOutput()
    @State private var zone: Zone?
    @State private var value: CGFloat = 0
    @State private var lastTranslation: CGSize = .zero
    @State private var direction: CGFloat = 1
    @State private var fired = false
    @State private var beganFullscreen = false
    @State private var targetTime: Double = 0
    @State private var cancelSeek = false
    @State private var lastVolumeUpdate: TimeInterval = 0
    @GestureState private var dragging = false

    private enum Zone { case brightness, volume, fullscreen, seek }

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 18, coordinateSpace: .local)
                        .updating($dragging) { _, active, _ in active = true }
                        .onChanged { drag in update(drag, size: geometry.size) }
                        .onEnded { _ in finish(cancelled: false) }
                        .exclusively(before: TapGesture().onEnded(onTap))
                )
                .overlay {
                    Text(readout)
                        .font(.callout.monospacedDigit().weight(.medium))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                        .position(x: geometry.size.width / 2, y: geometry.size.height * 0.76)
                        .opacity(zone == .brightness || zone == .volume || zone == .seek ? 1 : 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .background {
                    SystemGestureVolumeView(output: output)
                        .frame(width: 1, height: 1)
                        .clipped()
                        .opacity(0.001)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        }
        .onChange(of: dragging) { _, active in
            // SwiftUI 取消手势时不会调用 onEnded，仍要清理预览状态。
            if !active, zone != nil { finish(cancelled: true) }
        }
        .onChange(of: isFullScreen) { finish(cancelled: true) }
        .onDisappear { finish(cancelled: true) }
    }

    private var readout: String {
        if zone == .seek {
            return cancelSeek ? "松开取消跳转" : PlaybackTime.text(targetTime)
        }
        return "\(Int((value * 100).rounded()))"
    }

    private func update(_ drag: DragGesture.Value, size: CGSize) {
        if zone == nil {
            let dx = abs(drag.translation.width)
            let dy = abs(drag.translation.height)
            if dx > 3 * dy {
                guard duration.isFinite, duration > 0 else { return }
                zone = .seek
                targetTime = min(max(currentTime, 0), duration)
                cancelSeek = false
                onSeekChanged(targetTime)
            } else if dy > 3 * dx {
                let bounds = PlayerGestureSettings.boundaries(left: left, right: right)
                let x = drag.startLocation.x / max(size.width, 1)
                zone = x < bounds.0 ? .brightness : (x > bounds.1 ? .volume : .fullscreen)
                value = zone == .brightness ? output.brightness : output.volume
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

        let dx = drag.translation.width - lastTranslation.width
        let dy = (drag.translation.height - lastTranslation.height) * direction
        lastTranslation = drag.translation
        switch zone {
        case .seek:
            // 和 PiliPlus 一样，拖到画面上方左右各 1/8 的角落可以取消跳转。
            cancelSeek = drag.location.y <= size.height * 0.125
                && (drag.location.x <= size.width * 0.125 || drag.location.x >= size.width * 0.875)
            guard !cancelSeek else { return }
            targetTime = min(max(targetTime + Double(dx / max(size.width, 1)) * 90, 0), duration)
            onSeekChanged(targetTime)
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

    private func finish(cancelled: Bool) {
        let completedZone = zone
        zone = nil
        fired = false
        if completedZone == .volume { output.setVolume(value) }
        if completedZone == .seek {
            if cancelled || cancelSeek { onSeekCancelled() }
            else { onSeekEnded(targetTime) }
        }
        cancelSeek = false
    }
}

@MainActor
private final class PlayerGestureOutput {
    weak var view: MPVolumeView?
    var brightness: CGFloat { view?.window?.windowScene?.screen.brightness ?? 0.5 }
    var volume: CGFloat { CGFloat(AVAudioSession.sharedInstance().outputVolume) }
    func setBrightness(_ value: CGFloat) { view?.window?.windowScene?.screen.brightness = value }
    func setVolume(_ value: CGFloat) {
        guard let slider = view?.subviews.compactMap({ $0 as? UISlider }).first else { return }
        slider.setValue(Float(value), animated: false)
        slider.sendActions(for: .valueChanged)
    }
}

private struct SystemGestureVolumeView: UIViewRepresentable {
    let output: PlayerGestureOutput
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        output.view = view
        return view
    }
    func updateUIView(_ view: MPVolumeView, context: Context) { output.view = view }
    static func dismantleUIView(_ view: MPVolumeView, coordinator: ()) { }
}
