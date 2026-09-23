import SwiftUI

struct PlaybackSettingsView: View {
    @AppStorage(PlaybackWindowSettings.storageKey) private var miniPlayerEnabled = PlaybackWindowSettings.defaultValue
    @AppStorage("neobili.preferredQuality") private var preferredQuality = 64
    @AppStorage(PlaybackQuality.audioStorageKey) private var preferredAudioQuality = 0

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
            Section {
                Toggle("缩略播放器", isOn: $miniPlayerEnabled)
            } header: {
                Text("播放方式")
            } footer: {
                Text(miniPlayerEnabled ? "退出视频页面后在底部继续播放，底部标签栏可随滚动收缩。" : "退出视频页面后停止播放，底部标签栏始终保持展开。")
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
            Section {
                Toggle("隐藏竖屏视频", isOn: $hidesPortraitVideos)
            } header: {
                Text("画幅")
            } footer: {
                Text("应用于推荐、关注、搜索、收藏、历史等视频列表。")
            }
            Section {
                // 原来是 1 分钟一档的步进器，想设到 10 分钟要连点十次；改为常用档位。
                Picker("最短视频时长", selection: $durationFilter.minimumMinutes) {
                    ForEach(durationOptions, id: \.self) { minutes in
                        Text(minutes == 0 ? "不限制" : "\(minutes) 分钟").tag(minutes)
                    }
                }
            } header: {
                Text("时长")
            } footer: {
                Text("短于这个时长的视频会从这些列表中隐藏。")
            }
        }
        .settingsPage("内容过滤")
    }

    /// 常用档位；旧版本步进器存下的非整档值也保留为一个选项，不会被悄悄改掉。
    private var durationOptions: [Int] {
        let presets = [0, 1, 2, 3, 5, 10, 15, 20, 30, 60]
        let current = durationFilter.minimumMinutes
        return presets.contains(current) ? presets : (presets + [current]).sorted()
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

    private static let labels = ["最小", "较小", "小", "标准", "大", "较大", "最大"]

    static func label(for index: Int) -> String {
        labels[min(max(index, 0), labels.count - 1)]
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("当前档位", value: Self.label(for: textSizeIndex))
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
                Button("恢复标准") { textSizeIndex = AppTextSize.defaultIndex }
                    .disabled(textSizeIndex == AppTextSize.defaultIndex)
            } footer: {
                Text("App 内统一使用这里的文字大小，不跟随系统设置。")
            }
        }
        .settingsPage("文字大小")
    }
}

struct InteractionSettingsView: View {
    @Environment(\.appThemeColor) private var themeColor
    @AppStorage(HomeRefreshSettings.storageKey) private var refreshDistance = HomeRefreshSettings.defaultDistance
    @AppStorage(LeftEdgeTapDeadZone.storageKey) private var deadZoneWidth = LeftEdgeTapDeadZone.defaultWidth
    @State private var showsDeadZonePreview = false
    @State private var previewHideTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("下拉刷新距离", value: "\(Int(HomeRefreshSettings.clamped(refreshDistance))) pt")
                        .monospacedDigit()
                    Slider(value: $refreshDistance, in: HomeRefreshSettings.range, step: 5)
                        .accessibilityLabel("下拉刷新距离")
                        .accessibilityValue("\(Int(refreshDistance)) 点")
                }
            } header: {
                Text("滚动")
            } footer: {
                Text("推荐、直播和关注页共用。距离越短，越容易触发刷新。")
            }
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("左缘触控死区", value: "\(Int(deadZoneWidth)) pt")
                        .monospacedDigit()
                    Slider(value: Binding(get: { deadZoneWidth }, set: updateDeadZone),
                           in: 0...LeftEdgeTapDeadZone.maxWidth, step: 1)
                        .accessibilityLabel("左缘触控死区宽度")
                        .accessibilityValue("\(Int(deadZoneWidth)) 点")
                }
            } header: {
                Text("防误触")
            } footer: {
                Text("屏幕左缘这一窄条内的点按不生效，避免侧滑返回时误点到卡片。拖动滑杆时会高亮显示范围。")
            }
        }
        .settingsPage("滚动与防误触")
        .overlay(alignment: .leading) {
            if showsDeadZonePreview {
                Rectangle()
                    .fill(themeColor.opacity(0.22))
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(themeColor.opacity(0.85)).frame(width: 1.5)
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

extension View {
    func settingsPage(_ title: String) -> some View {
        leftEdgeTapDeadZone()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
