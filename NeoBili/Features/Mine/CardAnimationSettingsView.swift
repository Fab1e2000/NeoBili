import SwiftUI

struct CardAnimationSettingsView: View {
    @AppStorage(CardAnimationSettings.masterKey) private var enabled = CardAnimationSettings.defaultValue
    @AppStorage(CardAnimationSettings.dynamicExitKey) private var dynamicExit = CardAnimationSettings.defaultValue
    @AppStorage(CardAnimationSettings.pageEnterKey) private var pageEnter = CardAnimationSettings.defaultValue
    @AppStorage(AnimationSpeedSettings.exitSpeedKey) private var exitSpeed = AnimationSpeedSettings.defaultSpeed
    @AppStorage(AnimationSpeedSettings.enterSpeedKey) private var enterSpeed = AnimationSpeedSettings.defaultSpeed

    private var enabledEffects: [Bool] { [enabled, dynamicExit, pageEnter] }

    var body: some View {
        Form {
            Section {
                Toggle("自定义动画", isOn: $enabled)
                    .accessibilityIdentifier("settings.cardAnimations.enabled")
            }

            Section {
                ForEach(VideoCardAnimationSource.allCases.filter { !$0.supportedPhases.isEmpty && $0 != .live }) { source in
                    VideoCardAnimationSettingsLink(source: source)
                }
            } header: {
                Text("视频卡片")
            } footer: {
                Text("推荐、直播和搜索页面的卡片以原位淡入方式出现。")
            }
            .disabled(!enabled)

            Section("直播") {
                VideoCardAnimationSettingsLink(source: .live)
            }
            .disabled(!enabled)

            Section("动态卡片") {
                Toggle("退出动画", isOn: $dynamicExit)
                    .accessibilityIdentifier("settings.cardAnimations.dynamicExit")
            }
            .disabled(!enabled)

            Section("页面切换") {
                Toggle("页面淡入", isOn: $pageEnter)
                    .accessibilityIdentifier("settings.cardAnimations.pageEnter")
            }
            .disabled(!enabled)

            Section("动画速度") {
                AnimationSpeedSlider(title: "进入速度", value: $enterSpeed)
                AnimationSpeedSlider(title: "退出速度", value: $exitSpeed)
            }
            .disabled(!enabled)
        }
        .navigationTitle("动画")
        .navigationBarTitleDisplayMode(.inline)
        .leftEdgeTapDeadZone()
        .onChange(of: enabledEffects) { notifyChange() }
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: CardAnimationSettings.didChangeNotification, object: nil)
    }
}

private struct VideoCardAnimationSettingsLink: View {
    let source: VideoCardAnimationSource
    private var preferences: VideoCardAnimationPreferences

    init(source: VideoCardAnimationSource) {
        self.source = source
        preferences = VideoCardAnimationPreferences(source: source)
    }

    private var summary: String {
        let phases = source.supportedPhases.filter { preferences.isEnabled(phase: $0) }
        if phases.isEmpty { return "关闭" }
        if phases.count == source.supportedPhases.count { return "开启" }
        return phases.contains(.enter) ? "仅进入" : "仅退出"
    }

    var body: some View {
        NavigationLink {
            VideoCardSourceAnimationSettingsView(source: source)
        } label: {
            LabeledContent(source.title, value: summary)
        }
        .accessibilityIdentifier("settings.cardAnimations.source.\(source.rawValue)")
    }
}

private struct VideoCardSourceAnimationSettingsView: View {
    let source: VideoCardAnimationSource
    @AppStorage(CardAnimationSettings.masterKey) private var enabled = CardAnimationSettings.defaultValue
    @AppStorage(CardAnimationSettings.videoEnterKey) private var legacyEnter = CardAnimationSettings.defaultValue
    @AppStorage(CardAnimationSettings.videoExitKey) private var legacyExit = CardAnimationSettings.defaultValue
    @AppStorage private var enter: Bool?
    @AppStorage private var exit: Bool?

    init(source: VideoCardAnimationSource) {
        self.source = source
        _enter = AppStorage(CardAnimationSettings.storageKey(source: source, phase: .enter))
        _exit = AppStorage(CardAnimationSettings.storageKey(source: source, phase: .exit))
    }

    var body: some View {
        Form {
            Section {
                if source.supportedPhases.contains(.enter) {
                    Toggle("原位淡入", isOn: Binding(get: { enter ?? legacyEnter }, set: { enter = $0 }))
                        .accessibilityIdentifier("settings.cardAnimations.\(source.rawValue).enter")
                }
                if source.supportedPhases.contains(.exit) {
                    Toggle("退出动画", isOn: Binding(get: { exit ?? legacyExit }, set: { exit = $0 }))
                        .accessibilityIdentifier("settings.cardAnimations.\(source.rawValue).exit")
                }
            }
            .disabled(!enabled)
        }
        .navigationTitle(source.title)
        .navigationBarTitleDisplayMode(.inline)
        .leftEdgeTapDeadZone()
        .onChange(of: [enter, exit]) {
            NotificationCenter.default.post(name: CardAnimationSettings.didChangeNotification, object: nil)
        }
    }
}

private struct AnimationSpeedSlider: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.1f×", AnimationSpeedSettings.clamped(value)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: AnimationSpeedSettings.range, step: 0.1)
                .accessibilityLabel(title)
                .accessibilityValue(String(format: "%.1f 倍速", value))
        }
    }
}
