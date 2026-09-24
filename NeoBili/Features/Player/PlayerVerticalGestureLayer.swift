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
    var feedbackTopInset: CGFloat = 0
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
    @State private var seek: PlayerSeekGestureState?
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
                        .onEnded { drag in
                            if zone != nil { update(drag, size: geometry.size) }
                            finish(cancelled: false)
                        }
                        .exclusively(before: TapGesture().onEnded(onTap))
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
        .onChange(of: canSeek) { _, enabled in if !enabled { finish(cancelled: true) } }
        .onChange(of: isFullScreen) { finish(cancelled: true) }
        .onAppear { output.startObservingVolume() }
        .onDisappear {
            finish(cancelled: true)
            output.stopObservingVolume()
        }
    }

    @ViewBuilder
    private var feedback: some View {
        if let seek, zone == .seek {
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
        } else if zone == .brightness || zone == .volume || (zone == nil && output.externalVolume != nil) {
            let displayedValue = zone == nil ? (output.externalVolume ?? output.volume) : value
            Label("\(Int((displayedValue * 100).rounded()))%", systemImage: zone == .brightness ? "sun.max.fill" : "speaker.wave.2.fill")
                .font(.callout.monospacedDigit())
                .padding(12)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func update(_ drag: DragGesture.Value, size: CGSize) {
        if zone == nil {
            let dx = abs(drag.translation.width)
            let dy = abs(drag.translation.height)
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

    private func finish(cancelled: Bool) {
        let completedZone = zone
        zone = nil
        fired = false
        if completedZone == .volume { output.setVolume(value) }
        if completedZone == .seek, let seek {
            if cancelled || seek.isCancelled { onSeekCancelled() }
            else { onSeekEnded(seek.target) }
        }
        seek = nil
    }
}

@MainActor
@Observable
private final class PlayerGestureOutput {
    @ObservationIgnored weak var view: MPVolumeView?
    private(set) var externalVolume: CGFloat?
    @ObservationIgnored private var volumeObservation: NSKeyValueObservation?
    @ObservationIgnored private var hideVolumeTask: Task<Void, Never>?
    @ObservationIgnored private var observationID: UUID?
    @ObservationIgnored private var suppressVolumeEventsUntil: TimeInterval = 0

    func startObservingVolume() {
        guard volumeObservation == nil else { return }
        let id = UUID()
        observationID = id
        volumeObservation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
            let volume = CGFloat(session.outputVolume)
            let eventTime = ProcessInfo.processInfo.systemUptime
            Task { @MainActor [weak self] in
                guard let self, self.observationID == id,
                      eventTime >= self.suppressVolumeEventsUntil else { return }
                self.externalVolume = volume
                self.hideVolumeTask?.cancel()
                self.hideVolumeTask = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .milliseconds(800)) }
                    catch { return }
                    self?.externalVolume = nil
                }
            }
        }
    }

    func stopObservingVolume() {
        observationID = nil
        volumeObservation?.invalidate()
        volumeObservation = nil
        hideVolumeTask?.cancel()
        hideVolumeTask = nil
        externalVolume = nil
    }
    var brightness: CGFloat { view?.window?.windowScene?.screen.brightness ?? 0.5 }
    var volume: CGFloat { CGFloat(AVAudioSession.sharedInstance().outputVolume) }
    func setBrightness(_ value: CGFloat) { view?.window?.windowScene?.screen.brightness = value }
    func setVolume(_ value: CGFloat) {
        guard let slider = view?.subviews.compactMap({ $0 as? UISlider }).first else { return }
        // 手势写入也会产生系统音量通知；短暂忽略回声，避免松手后重复弹出提示。
        suppressVolumeEventsUntil = ProcessInfo.processInfo.systemUptime + 0.2
        hideVolumeTask?.cancel()
        externalVolume = nil
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
