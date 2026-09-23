import SwiftUI

struct DanmakuSettingsView: View {
    @AppStorage(DanmakuSettings.fontScaleKey) private var fontScale = 1.0
    @AppStorage(DanmakuSettings.opacityKey) private var opacity = 1.0
    @AppStorage(DanmakuSettings.blockTopKey) private var blockTop = false
    @AppStorage(DanmakuSettings.blockBottomKey) private var blockBottom = false
    @AppStorage(DanmakuSettings.coloredEnabledKey) private var colored = true

    var body: some View {
        Form {
            Section("实时预览") {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.13, green: 0.22, blue: 0.35), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "play.rectangle").font(.system(size: 48)).foregroundStyle(.white.opacity(0.2))
                    DanmakuSettingsPreview(fontScale: fontScale, opacity: opacity, blockTop: blockTop, blockBottom: blockBottom, colored: colored)
                }
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel("弹幕实时预览，包含滚动、顶部和底部弹幕")
            }
            Section("显示") {
                LabeledContent("字体尺寸", value: "\(Int(fontScale * 100))%")
                Slider(value: $fontScale, in: 0.7...1.8, step: 0.05).accessibilityLabel("弹幕字体尺寸")
                LabeledContent("不透明度", value: "\(Int(opacity * 100))%")
                Slider(value: $opacity, in: 0.1...1, step: 0.05).accessibilityLabel("弹幕不透明度")
                Toggle("彩色弹幕", isOn: $colored)
            }
            Section {
                Toggle("屏蔽顶部弹幕", isOn: $blockTop)
                Toggle("屏蔽底部弹幕", isOn: $blockBottom)
            } footer: {
                Text("屏蔽顶部或底部的固定弹幕，不影响滚动弹幕。显示设置应用于视频和直播画面上的弹幕。")
            }
            Section {
                Button("恢复默认设置") {
                    fontScale = 1; opacity = 1; blockTop = false; blockBottom = false; colored = true
                }
            }
        }
        .settingsPage("弹幕设置")
    }
}

/// Uses the playback renderer, including the same typography, opacity and filters.
private struct DanmakuSettingsPreview: UIViewRepresentable {
    let fontScale: Double
    let opacity: Double
    let blockTop: Bool
    let blockBottom: Bool
    let colored: Bool
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> DanmakuEngine {
        let engine = DanmakuEngine()
        engine.area = 1
        context.coordinator.engine = engine
        context.coordinator.timer = Timer(timeInterval: 0.1, repeats: true) { [weak coordinator = context.coordinator] _ in
            MainActor.assumeIsolated { coordinator?.tick() }
        }
        if let timer = context.coordinator.timer { RunLoop.main.add(timer, forMode: .common) }
        return engine
    }
    func updateUIView(_ engine: DanmakuEngine, context: Context) {
        engine.coloredEnabled = colored
        engine.applyAppearance(fontSize: 15 * fontScale, opacity: opacity, blockTop: blockTop, blockBottom: blockBottom)
        context.coordinator.restart()
        engine.update(currentTime: 0)
    }
    static func dismantleUIView(_ engine: DanmakuEngine, coordinator: Coordinator) {
        coordinator.timer?.invalidate()
        engine.removeFromSuperview()
    }
    @MainActor final class Coordinator {
        weak var engine: DanmakuEngine?
        var timer: Timer?
        var time = 0.0
        func restart() {
            time = 0
            engine?.prepare(items: [
                DanmakuItem(time: 0, text: "顶部弹幕 · 实时预览", mode: 5, color: 0xFFFFFF),
                DanmakuItem(time: 0, text: "底部弹幕 · 实时预览", mode: 4, color: 0xFFFFFF),
                DanmakuItem(time: 0.2, text: "滚动弹幕，看看这个字号", mode: 1, color: 0xFFFFFF),
                DanmakuItem(time: 0.8, text: "彩色弹幕也会同步更新", mode: 1, color: 0x80D8FF)
            ])
        }
        func tick() {
            guard let engine, engine.window != nil, engine.bounds.width > 10 else { return }
            if time == 0 { restart() }
            if time >= 7 { restart() }
            engine.update(currentTime: time)
            time += 0.1
        }
    }
}
