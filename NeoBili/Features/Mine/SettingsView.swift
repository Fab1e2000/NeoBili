import SwiftUI

/// 系统设置。当前仅包含播放偏好与账号管理，后续设置项都加进这里。
struct SettingsView: View {
    @Environment(AccountStore.self) private var account

    /// 与 `VideoPlaybackConfiguration.current` 共用的键。改动对之后新打开的视频生效。
    @AppStorage("neobili.preferredQuality") private var preferredQuality = 64
    /// 文字大小档位。根视图读同一个键，拖完滑杆全 App 立刻跟着变。
    @AppStorage(AppTextSize.storageKey) private var textSizeIndex = AppTextSize.defaultIndex
    /// 左缘触控死区宽度。各页面的死区都读这同一个键。
    @AppStorage(LeftEdgeTapDeadZone.storageKey) private var edgeDeadZoneWidth = LeftEdgeTapDeadZone.defaultWidth
    /// 拖动死区滑杆期间在屏幕左缘亮起的实时遮罩，停手后自动淡出。
    @State private var isShowingDeadZonePreview = false
    @State private var deadZonePreviewHideTask: Task<Void, Never>?
    @State private var confirmLogout = false
    @AppStorage(FollowingSidebarSide.storageKey) private var followingSidebarSide: FollowingSidebarSide = .left
    @AppStorage(FollowingSidebarLayout.countKey) private var followingSidebarCount = FollowingSidebarLayout.defaultCount
    @AppStorage(FollowingSidebarDwellSettings.storageKey) private var followingSidebarDwellDuration = FollowingSidebarDwellSettings.defaultDuration
    @AppStorage(HomeRefreshSettings.storageKey) private var homeRefreshDistance = HomeRefreshSettings.defaultDistance
    /// 刷新动画的快慢。退出＝旧卡片淡出，进入＝新卡片落位，两段分开调。
    @AppStorage(AnimationSpeedSettings.exitSpeedKey) private var feedExitSpeed = AnimationSpeedSettings.defaultSpeed
    @AppStorage(AnimationSpeedSettings.enterSpeedKey) private var feedEnterSpeed = AnimationSpeedSettings.defaultSpeed

    /// 清晰度选项的展示名。实际可用上限取决于账号等级与稿件本身。
    private static let qualityOptions: [(qn: Int, label: String)] = [
        (16, "360P 流畅"),
        (32, "480P 清晰"),
        (64, "720P 高清"),
        (80, "1080P 高清"),
        (112, "1080P 高码率")
    ]

    var body: some View {
        Form {
            Section {
                Picker("默认清晰度", selection: $preferredQuality) {
                    ForEach(Self.qualityOptions, id: \.qn) { option in
                        Text(option.label).tag(option.qn)
                    }
                }
            } header: {
                Text("播放")
            } footer: {
                Text("对之后打开的视频生效。可用画质还受账号等级和稿件本身的限制。")
            }

            PlayerGestureSettingsSection()

            Section {
                Picker("头像列表位置", selection: $followingSidebarSide) {
                    ForEach(FollowingSidebarSide.allCases) { side in
                        Text(side.title).tag(side)
                    }
                }
                Picker("选择器显示数量", selection: $followingSidebarCount) {
                    ForEach(FollowingSidebarLayout.counts, id: \.self) { count in
                        Text("\(count) 个").tag(count)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("头像停留判定时间")
                        Spacer()
                        Text("\(FollowingSidebarDwellSettings.clamped(followingSidebarDwellDuration), specifier: "%.1f") 秒")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $followingSidebarDwellDuration, in: FollowingSidebarDwellSettings.range, step: 0.1)
                        .accessibilityLabel("头像停留判定时间")
                        .accessibilityValue("\(FollowingSidebarDwellSettings.clamped(followingSidebarDwellDuration), specifier: "%.1f") 秒")
                }
            } header: {
                Text("关注页")
            } footer: {
                Text("页面右滑或触碰侧边头像可展开选择器；展开后在页面任意位置上下滑动均可选择，左滑或轻点选择器外部收起。头像焦点停留达到判定时间后自动刷新对应页面，默认 0.5 秒，可调 0.1–2 秒。显示数量默认 7 个，高度会适应屏幕可用空间。")
            }

            Section {
                textSizeSlider
            } header: {
                Text("显示")
            } footer: {
                Text("App 内所有文字按这个档位显示，不跟随系统「设置 → 显示与亮度 → 文字大小」——两边同时缩放会让排版不可预期。")
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("下拉刷新距离")
                        Spacer()
                        Text("\(Int(HomeRefreshSettings.clamped(homeRefreshDistance))) pt")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $homeRefreshDistance, in: HomeRefreshSettings.range, step: 5)
                        .accessibilityLabel("推荐与关注下拉刷新距离")
                        .accessibilityValue("\(Int(homeRefreshDistance)) 点")
                    HStack {
                        Text("更灵敏")
                        Spacer()
                        Text("不易误触")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("下拉刷新")
            } footer: {
                Text("推荐与关注页共用此设置。手指下拉达到设定距离后轻震，松手刷新，回推可取消。默认 70pt。再次点击底部「推荐」可回到顶部；已在顶部时点击则刷新。")
            }

            Section {
                animationSpeedSlider(
                    title: "退出动画",
                    value: $feedExitSpeed,
                    accessibilityLabel: "刷新退出动画速度"
                )
                animationSpeedSlider(
                    title: "进入动画",
                    value: $feedEnterSpeed,
                    accessibilityLabel: "刷新进入动画速度"
                )
            } header: {
                Text("动画")
            } footer: {
                Text("推荐与关注刷新：退出＝松手后旧卡片原地淡尽，与网络无关；进入＝新卡片从上方逐行落位。数据来得快就等淡出走完再落位，来得慢则中间是一段空屏。\n主页面切换：新页面淡入，只受进入倍率影响，时长比刷新短。\n倍率越大越快，1.0× 是默认速度。开启系统「减弱动效」后一律不播。")
            }

            Section {
                edgeDeadZoneSlider
            } header: {
                Text("防误触")
            } footer: {
                Text("屏幕左缘这一小条内的点击不生效，避免滑动返回时误触卡片；滑动返回不受影响。在这条里起手的竖向滚动也滚不动列表，调到 0 即关闭。")
            }

            Section("账号") {
                if let profile = account.profile {
                    LabeledContent("当前用户", value: profile.name)
                    LabeledContent("UID", value: String(profile.mid))
                }
                Button("退出登录", role: .destructive) {
                    confirmLogout = true
                }
                .disabled(!account.isLoggedIn)
            }

            Section("关于") {
                LabeledContent("版本", value: Self.appVersion)
                LabeledContent("界面修订", value: Self.uiRevision)
                LabeledContent("播放内核", value: "mpv (MPVKit)")
                LabeledContent("接口与交互参考", value: "PiliPlus / MeloX")
            }
        }
        // 左缘一小条是触控死区：点击不生效，避免滑动返回时误触条目。
        .leftEdgeTapDeadZone()
        .navigationTitle("系统设置")
        // 拖动「左缘触控死区」滑杆时，屏幕左缘亮起一条实时遮罩标出当前
        // 宽度，停手后自动淡出。遮罩只是给人看的，不参与命中测试。
        .overlay(alignment: .leading) {
            if isShowingDeadZonePreview {
                Rectangle()
                    .fill(Color.accentColor.opacity(0.22))
                    .overlay(alignment: .trailing) {
                        // 右缘一道实线，宽度很小时也能看清遮罩到哪儿为止。
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.85))
                            .frame(width: 1.5)
                    }
                    .frame(width: edgeDeadZoneWidth)
                    // 伸到状态栏和屏幕底部之外，标的是「屏幕左缘」而不是表单左缘。
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "退出登录后将回到访客模式，推荐不再个性化；需要重新登录才能使用收藏等功能。确定退出？",
            isPresented: $confirmLogout,
            titleVisibility: .visible
        ) {
            Button("退出登录", role: .destructive) {
                Task { await account.logout() }
            }
            Button("取消", role: .cancel, action: {})
        }
    }

    /// 仿系统「文字大小」那一页：两端是「小」「大」，中间七个刻度。
    /// 两条动画速度滑杆长得一样，只有标题和绑定不同。
    private func animationSpeedSlider(
        title: String,
        value: Binding<Double>,
        accessibilityLabel: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.1f×", AnimationSpeedSettings.clamped(value.wrappedValue)))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: AnimationSpeedSettings.range, step: 0.1)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue(String(format: "%.1f 倍速", value.wrappedValue))
            HStack {
                Text("更舒缓")
                Spacer()
                Text("更利落")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var textSizeSlider: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 拖动时这一行会跟着当前档位一起放大缩小，等于就地预览。
            Text("正文预览：这段文字会随档位一起变化")
                .font(.body)
                .foregroundStyle(.secondary)
                .dynamicTypeSize(AppTextSize.size(at: textSizeIndex))

            HStack(spacing: 12) {
                Text("小")
                    .font(.footnote)

                Slider(
                    value: Binding(
                        get: { Double(textSizeIndex) },
                        set: { textSizeIndex = Int($0.rounded()) }
                    ),
                    in: 0...Double(AppTextSize.steps.count - 1),
                    step: 1
                )
                .accessibilityLabel("文字大小")
                .accessibilityValue("第 \(textSizeIndex + 1) 档，共 \(AppTextSize.steps.count) 档")

                Text("大")
                    .font(.title3)
            }
            // 两端的「小」「大」是刻度标签，不该跟着档位一起缩放，
            // 否则拖到最大时它们会把滑杆挤没。
            .dynamicTypeSize(.large)
        }
        .padding(.vertical, 4)
    }

    /// 左缘触控死区的宽度滑杆，样式仿文字大小那一行。
    ///
    /// 拖动时屏幕左缘出现一条实时遮罩（见 body 里的 overlay），当前宽度
    /// 挡住多少内容一眼可见；停手约一秒后遮罩自动淡出。
    private var edgeDeadZoneSlider: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("左缘触控死区")
                Spacer()
                Text("\(Int(edgeDeadZoneWidth))pt")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(
                value: Binding(
                    get: { edgeDeadZoneWidth },
                    set: { newValue in
                        edgeDeadZoneWidth = newValue.rounded()
                        revealDeadZonePreview()
                    }
                ),
                in: 0...LeftEdgeTapDeadZone.maxWidth,
                step: 1
            )
            .accessibilityLabel("左缘触控死区宽度")
            .accessibilityValue("\(Int(edgeDeadZoneWidth)) 点")
        }
        .padding(.vertical, 4)
    }

    /// 亮起左缘遮罩，并安排在最后一次拖动之后一秒淡出。
    private func revealDeadZonePreview() {
        if !isShowingDeadZonePreview {
            withAnimation(.easeOut(duration: 0.15)) { isShowingDeadZonePreview = true }
        }
        deadZonePreviewHideTask?.cancel()
        deadZonePreviewHideTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.45)) { isShowingDeadZonePreview = false }
        }
    }

    private static var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    /// 每次 UI 行为调整后手动更新。设置页可见 + 二进制里可 grep（长度必须
    /// 超过 15 字节，否则会被 Swift 小字符串优化内联进机器码导致搜不到）。
    private static let uiRevision = "following-top-inset-20260907"
}
