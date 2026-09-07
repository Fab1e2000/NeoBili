import SwiftUI
import UIKit
import MediaPlayer
import AVFAudio

/// 放在播放按钮和进度条后面，控件本身的点击/拖动优先。
struct PlayerVerticalGestureLayer: View {
    let isFullScreen: Bool
    let onTap: () -> Void
    let onToggleFullScreen: () -> Void
    @AppStorage(PlayerGestureSettings.leftKey) private var left = 0.33
    @AppStorage(PlayerGestureSettings.rightKey) private var right = 0.67
    @AppStorage(PlayerGestureSettings.reverseKey) private var reversed = false
    @State private var output = PlayerGestureOutput()
    @State private var zone: Zone?
    @State private var initialValue: CGFloat = 0
    @State private var value: CGFloat = 0
    @State private var direction: CGFloat = 1
    @State private var fired = false
    @State private var beganFullscreen = false

    private enum Zone { case brightness, volume, fullscreen }

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 6, coordinateSpace: .local)
                        .onChanged { drag in update(drag, size: geometry.size) }
                        .onEnded { _ in zone = nil; fired = false }
                        .exclusively(before: TapGesture().onEnded(onTap))
                )
                .overlay {
                    // 只显示读数，不用面板、图标或进度条遮住画面。
                    Text("\(Int((value * 100).rounded()))")
                        .font(.callout.monospacedDigit().weight(.medium))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                        .position(x: geometry.size.width / 2, y: geometry.size.height * 0.76)
                        .opacity(zone == .brightness || zone == .volume ? 1 : 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .background {
                    // 保留系统音量接口和所属屏幕，原生滑杆不参与显示或触摸。
                    SystemGestureVolumeView(output: output)
                        .frame(width: 1, height: 1)
                        .clipped()
                        .opacity(0.001)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        }
        .onDisappear { zone = nil; fired = false }
    }

    private func update(_ drag: DragGesture.Value, size: CGSize) {
        if zone == nil {
            guard abs(drag.translation.height) > abs(drag.translation.width) else { return }
            let bounds = PlayerGestureSettings.boundaries(left: left, right: right)
            let x = drag.startLocation.x / max(size.width, 1)
            zone = x < bounds.0 ? .brightness : (x > bounds.1 ? .volume : .fullscreen)
            direction = reversed ? -1 : 1
            beganFullscreen = isFullScreen
            fired = false
            initialValue = zone == .brightness ? output.brightness : output.volume
        }
        let dy = drag.translation.height * direction
        switch zone {
        case .brightness, .volume:
            value = min(max(initialValue - dy / max(size.height * 0.7, 120), 0), 1)
            if zone == .brightness { output.setBrightness(value) } else { output.setVolume(value) }
        case .fullscreen:
            let threshold: CGFloat = 22
            guard !fired, beganFullscreen ? dy < -threshold : dy > threshold else { return }
            fired = true
            onToggleFullScreen()
        default: break
        }
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
