import SwiftUI

struct PlaybackSettingsView: View {
    @AppStorage("neobili.preferredQuality") private var preferredQuality = 64
    @AppStorage(PlaybackQuality.audioStorageKey) private var preferredAudioQuality = 0
    @AppStorage(PlaybackWindowSettings.storageKey) private var miniPlayerEnabled = PlaybackWindowSettings.defaultValue

    var body: some View {
        Form {
            Section("默认画质") {
                Picker("分辨率", selection: $preferredQuality) {
                    ForEach(PlaybackQuality.videoOptions, id: \.id) { option in
                        Text(option.title).tag(option.id)
                    }
                }
                Picker("音质", selection: $preferredAudioQuality) {
                    ForEach(PlaybackQuality.audioOptions, id: \.id) { option in
                        Text(option.title).tag(option.id)
                    }
                }
            }
            Section("播放方式") {
                Toggle("小窗播放", isOn: $miniPlayerEnabled)
                    .accessibilityIdentifier("settings.miniPlayer.enabled")
            }
        }
        .settingsPage("播放与画质")
    }
}

struct PlayerGestureSettingsView: View {
    var body: some View {
        Form { PlayerGestureSettingsSection() }
            .settingsPage("播放器手势")
    }
}

struct ContentFilterSettingsView: View {
    @Bindable private var durationFilter = VideoDurationFilterSettings.shared
    @AppStorage(PortraitVideoFilterSettings.storageKey) private var hidesPortraitVideos = PortraitVideoFilterSettings.defaultValue

    var body: some View {
        Form {
            Section("画幅") {
                Toggle("隐藏竖屏视频", isOn: $hidesPortraitVideos)
            }
            Section("时长") {
                Stepper(value: $durationFilter.minimumMinutes, in: 0...1440) {
                    LabeledContent("最短视频时长", value: durationFilter.minimumMinutes == 0 ? "不限制" : "\(durationFilter.minimumMinutes) 分钟")
                }
            }
        }
        .settingsPage("内容过滤")
    }
}

struct FollowingSettingsView: View {
    @AppStorage(FollowingSidebarSide.storageKey) private var side: FollowingSidebarSide = .left
    @AppStorage(FollowingSidebarLayout.countKey) private var count = FollowingSidebarLayout.defaultCount
    @AppStorage(FollowingSidebarDwellSettings.storageKey) private var dwellDuration = FollowingSidebarDwellSettings.defaultDuration

    var body: some View {
        Form {
            Section("选择器") {
                Picker("头像列表位置", selection: $side) {
                    ForEach(FollowingSidebarSide.allCases) { side in
                        Text(side.title).tag(side)
                    }
                }
                Picker("显示数量", selection: $count) {
                    ForEach(FollowingSidebarLayout.counts, id: \.self) { count in
                        Text("\(count) 个").tag(count)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("停留判定时间", value: String(format: "%.1f 秒", FollowingSidebarDwellSettings.clamped(dwellDuration)))
                        .monospacedDigit()
                    Slider(value: $dwellDuration, in: FollowingSidebarDwellSettings.range, step: 0.1)
                        .accessibilityLabel("头像停留判定时间")
                        .accessibilityValue("\(FollowingSidebarDwellSettings.clamped(dwellDuration), specifier: "%.1f") 秒")
                }
            }
        }
        .settingsPage("关注页")
    }
}

struct DisplaySettingsView: View {
    @AppStorage(AppTextSize.storageKey) private var textSizeIndex = AppTextSize.defaultIndex

    var body: some View {
        Form {
            Section {
                Text("正文预览：这段文字会随档位一起变化")
                    .font(.body)
                    .dynamicTypeSize(AppTextSize.size(at: textSizeIndex))
                    .padding(.vertical, 12)
                HStack(spacing: 12) {
                    Text("小").font(.footnote)
                    Slider(
                        value: Binding(get: { Double(textSizeIndex) }, set: { textSizeIndex = Int($0.rounded()) }),
                        in: 0...Double(AppTextSize.steps.count - 1), step: 1
                    )
                    .accessibilityLabel("文字大小")
                    .accessibilityValue("第 \(textSizeIndex + 1) 档，共 \(AppTextSize.steps.count) 档")
                    Text("大").font(.title3)
                }
                .dynamicTypeSize(.large)
            }
        }
        .settingsPage("文字大小")
    }
}

struct InteractionSettingsView: View {
    @AppStorage(HomeRefreshSettings.storageKey) private var refreshDistance = HomeRefreshSettings.defaultDistance
    @AppStorage(LeftEdgeTapDeadZone.storageKey) private var deadZoneWidth = LeftEdgeTapDeadZone.defaultWidth
    @State private var showsDeadZonePreview = false
    @State private var previewHideTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("滚动") {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("下拉刷新距离", value: "\(Int(HomeRefreshSettings.clamped(refreshDistance))) pt")
                        .monospacedDigit()
                    Slider(value: $refreshDistance, in: HomeRefreshSettings.range, step: 5)
                        .accessibilityLabel("推荐与关注下拉刷新距离")
                        .accessibilityValue("\(Int(refreshDistance)) 点")
                }
            }
            Section("防误触") {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("左缘触控死区", value: "\(Int(deadZoneWidth)) pt")
                        .monospacedDigit()
                    Slider(value: Binding(get: { deadZoneWidth }, set: updateDeadZone),
                           in: 0...LeftEdgeTapDeadZone.maxWidth, step: 1)
                        .accessibilityLabel("左缘触控死区宽度")
                        .accessibilityValue("\(Int(deadZoneWidth)) 点")
                }
            }
        }
        .settingsPage("滚动与防误触")
        .overlay(alignment: .leading) {
            if showsDeadZonePreview {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.22))
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(Color.accentColor.opacity(0.85)).frame(width: 1.5)
                    }
                    .frame(width: deadZoneWidth)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onDisappear { previewHideTask?.cancel() }
    }

    private func updateDeadZone(_ value: Double) {
        deadZoneWidth = value.rounded()
        if !showsDeadZonePreview {
            withAnimation(.easeOut(duration: 0.15)) { showsDeadZonePreview = true }
        }
        previewHideTask?.cancel()
        previewHideTask = Task {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            withAnimation(.easeIn(duration: 0.45)) { showsDeadZonePreview = false }
        }
    }
}

struct AccountSettingsView: View {
    @Environment(AccountStore.self) private var account
    @State private var confirmLogout = false

    var body: some View {
        Form {
            Section {
                if let profile = account.profile {
                    LabeledContent("当前用户", value: profile.name)
                    LabeledContent("UID", value: String(profile.mid))
                }
                Button("退出登录", role: .destructive) { confirmLogout = true }
                    .disabled(!account.isLoggedIn)
            }
        }
        .settingsPage("账号管理")
        .confirmationDialog("确定退出登录？", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { Task { await account.logout() } }
            Button("取消", role: .cancel, action: {})
        }
    }
}

struct AboutSettingsView: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("版本", value: appVersion)
                LabeledContent("界面修订", value: "settings-by-source-20260910")
                LabeledContent("播放内核", value: "mpv (MPVKit)")
                LabeledContent("接口与交互参考", value: "PiliPlus / MeloX")
            }
        }
        .settingsPage("关于")
    }

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }
}

private extension View {
    func settingsPage(_ title: String) -> some View {
        leftEdgeTapDeadZone()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
