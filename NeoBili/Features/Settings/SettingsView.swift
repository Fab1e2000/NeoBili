import SwiftUI

/// 设置首页。按「外观 → 页面 → 播放 → 内容与交互 → 账号」排列：
/// 越常调整、越影响整体观感的越靠前；每行右侧给出当前值，不必点进去就能看到。
struct SettingsView: View {
    @AppStorage(AppTheme.storageKey) private var themeID = AppTheme.defaultID
    @AppStorage(AppTextSize.storageKey) private var textSizeIndex = AppTextSize.defaultIndex
    @AppStorage(CardAnimationSettings.masterKey) private var cardAnimationsEnabled = CardAnimationSettings.defaultValue
    @AppStorage(MainTabSettings.orderKey) private var tabOrder = MainTabSettings.stored(MainTabSettings.defaultOrder)
    @AppStorage(MainTabSettings.hiddenKey) private var hiddenTabs: String?
    @AppStorage(TitleBarSettings.storageKey) private var pinsTitleBar = TitleBarSettings.defaultValue
    @AppStorage(PortraitVideoFilterSettings.storageKey) private var hidesPortraitVideos = PortraitVideoFilterSettings.defaultValue
    @State private var durationFilter = VideoDurationFilterSettings.shared

    var body: some View {
        Form {
            Section("外观") {
                row("主题色", value: AppTheme.selected(themeID).name, id: "theme") { ThemeSettingsView() }
                row("文字大小", value: DisplaySettingsView.label(for: textSizeIndex), id: "display") { DisplaySettingsView() }
                row("动画", value: cardAnimationsEnabled ? "开启" : "关闭", id: "cardAnimations") { CardAnimationSettingsView() }
            }

            Section("页面") {
                row("标签栏", value: MainTabSettings.visible(order: tabOrder, hidden: hiddenTabs).map(\.title).joined(separator: " · "),
                    id: "tabBar") { TabBarSettingsView() }
                row("标题栏", value: TitleBarSettings.summary(pinned: pinsTitleBar), id: "titleBar") { TitleBarSettingsView() }
                row("关注页", id: "following") { FollowingSettingsView() }
            }

            Section("播放") {
                row("播放与画质", id: "playback") { PlaybackSettingsView() }
                row("弹幕", id: "danmaku") { DanmakuSettingsView() }
                row("播放器手势", id: "playerGestures") { PlayerGestureSettingsView() }
                row("播放器控件位置", id: "playerChrome") { PlayerChromeSettingsView() }
            }

            Section("内容与交互") {
                row("内容过滤", value: contentFilterSummary, id: "contentFilter") { ContentFilterSettingsView() }
                row("滚动与防误触", id: "scrolling") { InteractionSettingsView() }
            }

            Section {
                row("账号管理", id: "account") { AccountSettingsView() }
                row("关于", id: "about") { AboutSettingsView() }
            }
        }
        .leftEdgeTapDeadZone()
        .navigationTitle("系统设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var contentFilterSummary: String {
        let active = (hidesPortraitVideos ? 1 : 0) + (durationFilter.minimumMinutes > 0 ? 1 : 0)
        return active == 0 ? "未开启" : "\(active) 项"
    }

    private func row<Destination: View>(_ title: String, value: String? = nil, id: String,
                                        @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink(destination: destination) {
            if let value {
                LabeledContent(title, value: value)
            } else {
                Text(title)
            }
        }
        .accessibilityIdentifier("settings.\(id)")
    }
}
