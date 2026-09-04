import SwiftUI

/// 系统设置。当前仅包含播放偏好与账号管理，后续设置项都加进这里。
struct SettingsView: View {
    @Environment(AccountStore.self) private var account

    /// 与 `VideoPlaybackConfiguration.current` 共用的键。改动对之后新打开的视频生效。
    @AppStorage("neobili.preferredQuality") private var preferredQuality = 64
    @State private var confirmLogout = false

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
        .navigationTitle("系统设置")
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

    private static var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    /// 每次 UI 行为调整后手动更新。设置页可见 + 二进制里可 grep（长度必须
    /// 超过 15 字节，否则会被 Swift 小字符串优化内联进机器码导致搜不到）。
    private static let uiRevision = "zoom-unify-1-20260904"
}
