import SwiftUI

struct SettingsView: View {
    @AppStorage(AppTheme.storageKey) private var themeID = AppTheme.defaultID
    @AppStorage(CardAnimationSettings.masterKey) private var cardAnimationsEnabled = CardAnimationSettings.defaultValue

    var body: some View {
        Form {
            Section("播放") {
                NavigationLink("播放与画质") { PlaybackSettingsView() }
                    .accessibilityIdentifier("settings.playback")
                NavigationLink("弹幕设置") { DanmakuSettingsView() }
                    .accessibilityIdentifier("settings.danmaku")
                NavigationLink("播放器手势") { PlayerGestureSettingsView() }
                    .accessibilityIdentifier("settings.playerGestures")
            }

            Section("内容") {
                NavigationLink("内容过滤") { ContentFilterSettingsView() }
                    .accessibilityIdentifier("settings.contentFilter")
                NavigationLink("关注页") { FollowingSettingsView() }
                    .accessibilityIdentifier("settings.following")
            }

            Section("界面与交互") {
                NavigationLink {
                    ThemeSettingsView()
                } label: {
                    LabeledContent("主题色", value: AppTheme.selected(themeID).name)
                }
                .accessibilityIdentifier("settings.theme")
                NavigationLink("文字大小") { DisplaySettingsView() }
                    .accessibilityIdentifier("settings.display")
                NavigationLink {
                    CardAnimationSettingsView()
                } label: {
                    LabeledContent("动画", value: cardAnimationsEnabled ? "开启" : "关闭")
                }
                .accessibilityIdentifier("settings.cardAnimations")
                NavigationLink("滚动与防误触") { InteractionSettingsView() }
                    .accessibilityIdentifier("settings.scrolling")
            }

            Section {
                NavigationLink("账号管理") { AccountSettingsView() }
                    .accessibilityIdentifier("settings.account")
                NavigationLink("关于") { AboutSettingsView() }
                    .accessibilityIdentifier("settings.about")
            }
        }
        .leftEdgeTapDeadZone()
        .navigationTitle("系统设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}
