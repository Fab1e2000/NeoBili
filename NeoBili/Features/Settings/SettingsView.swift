import SwiftUI

/// 设置首页。按「外观 → 浏览 → 播放 → 高级 → 账号」排列：
/// 越常调整、越影响整体观感的越靠前；动画速度、手势分区、控件位置这类细调收进「高级」。
/// 每行右侧给出当前值，不必点进去就能看到。
struct SettingsView: View {
    @AppStorage(AppTheme.storageKey) private var themeID = AppTheme.defaultID
    @AppStorage(AppTextSize.storageKey) private var textSizeIndex = AppTextSize.defaultIndex
    @AppStorage(CardAnimationSettings.masterKey) private var cardAnimationsEnabled = CardAnimationSettings.defaultValue
    @AppStorage(MainTabSettings.orderKey) private var tabOrder = MainTabSettings.stored(MainTabSettings.defaultOrder)
    @AppStorage(MainTabSettings.hiddenKey) private var hiddenTabs: String?
    @AppStorage(TitleBarSettings.storageKey) private var pinsTitleBar = TitleBarSettings.defaultValue
    @AppStorage(PortraitVideoFilterSettings.storageKey) private var hidesPortraitVideos = PortraitVideoFilterSettings.defaultValue
    @State private var durationFilter = VideoDurationFilterSettings.shared
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system

    var body: some View {
        Form {
            Section("外观") {
                row("主题色", value: AppTheme.selected(themeID).name, id: "theme") { ThemeSettingsView() }
                row("文字大小", value: DisplaySettingsView.label(for: textSizeIndex), id: "display") { DisplaySettingsView() }
                row("语言", value: language.title, id: "language") { LanguageSettingsView() }
            }

            Section("浏览") {
                row("标签栏", value: MainTabSettings.visible(order: tabOrder, hidden: hiddenTabs).map(\.title).joined(separator: " · "),
                    id: "tabBar") { TabBarSettingsView() }
                row("标题栏", value: TitleBarSettings.summary(pinned: pinsTitleBar), id: "titleBar") { TitleBarSettingsView() }
                row("内容过滤", value: contentFilterSummary, id: "contentFilter") { ContentFilterSettingsView() }
            }

            Section("播放") {
                row("播放与画质", id: "playback") { PlaybackSettingsView() }
                row("弹幕", id: "danmaku") { DanmakuSettingsView() }
            }

            Section {
                row("动画", value: cardAnimationsEnabled ? String(localized: "开启") : String(localized: "setting.off", defaultValue: "关闭"), id: "cardAnimations") { CardAnimationSettingsView() }
                row("播放器手势", id: "playerGestures") { PlayerGestureSettingsView() }
                row("播放器控件位置", id: "playerChrome") { PlayerChromeSettingsView() }
                row("滚动与防误触", id: "scrolling") { InteractionSettingsView() }
            } header: {
                Text("高级")
            } footer: {
                Text("动画速度、手势分区、控件位置和防误触的细调，一般保持默认即可。")
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
        return active == 0 ? String(localized: "未开启") : String(localized: "\(active) 项")
    }

    private func row<Destination: View>(_ title: LocalizedStringKey, value: String? = nil, id: String,
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
