import SwiftUI

/// 设置目录只负责导航与摘要；存储键和默认值由各设置类型维护。
struct SettingsView: View {
    @AppStorage(AppTheme.storageKey) private var themeID = AppTheme.defaultID
    @AppStorage(AppTextSize.storageKey) private var textSizeIndex = AppTextSize.defaultIndex
    @AppStorage(CardAnimationSettings.masterKey) private var cardAnimationsEnabled = CardAnimationSettings.defaultValue
    @AppStorage(MainTabSettings.orderKey) private var tabOrder = MainTabSettings.stored(MainTabSettings.defaultOrder)
    @AppStorage(MainTabSettings.hiddenKey) private var hiddenTabs: String?
    @TitleBarPreference private var titleBarStyle
    @AppStorage(PortraitVideoFilterSettings.storageKey) private var hidesPortraitVideos = PortraitVideoFilterSettings.defaultValue
    @AppStorage(RecommendationFilter.minLikeRatioKey) private var minLikeRatio = 0
    @AppStorage(RecommendationFilter.minDurationKey) private var minDuration = 0
    @AppStorage(RecommendationFilter.minPlayKey) private var minPlay = 0
    @AppStorage(RecommendationFilter.titleBanWordKey) private var titleKeywords = ""
    @AppStorage(RecommendationFilter.zoneBanWordKey) private var zoneKeywords = ""
    @State private var durationFilter = VideoDurationFilterSettings.shared
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.system

    var body: some View {
        Form {
            ForEach(SettingsCategory.allCases) { category in
                Section(category.title) {
                    ForEach(category.destinations) { destination in
                        NavigationLink {
                            destinationView(destination)
                        } label: {
                            if let summary = summary(for: destination) {
                                LabeledContent(destination.title, value: summary)
                            } else { Text(destination.title) }
                        }
                        .accessibilityIdentifier("settings.\(destination.rawValue)")
                    }
                }
            }
        }
        .leftEdgeTapDeadZone()
        .navigationTitle("系统设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var contentFilterSummary: String {
        let active = [hidesPortraitVideos, durationFilter.minimumMinutes > 0,
                      minLikeRatio > 0, minDuration > 0, minPlay > 0,
                      !titleKeywords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !zoneKeywords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty].filter { $0 }.count
        return active == 0 ? String(localized: "未开启") : String(localized: "\(active) 项")
    }

    private func summary(for destination: SettingsDestination) -> String? {
        switch destination {
        case .theme: AppTheme.selected(themeID).name
        case .display: DisplaySettingsView.label(for: textSizeIndex)
        case .language: language.title
        case .tabBar: MainTabSettings.visible(order: tabOrder, hidden: hiddenTabs).map(\.title).joined(separator: " · ")
        case .titleBar: titleBarStyle.title
        case .contentFilter: contentFilterSummary
        case .cardAnimations: cardAnimationsEnabled ? String(localized: "开启") : String(localized: "setting.off", defaultValue: "关闭")
        default: nil
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: SettingsDestination) -> some View {
        switch destination {
        case .theme: ThemeSettingsView()
        case .display: DisplaySettingsView()
        case .language: LanguageSettingsView()
        case .tabBar: TabBarSettingsView()
        case .titleBar: TitleBarSettingsView()
        case .contentFilter: ContentFilterSettingsView()
        case .recommendation: RecommendationSettingsView()
        case .playback: PlaybackSettingsView()
        case .danmaku: DanmakuSettingsView()
        case .deviceIdentity: DeviceIdentitySettingsView()
        case .cardAnimations: CardAnimationSettingsView()
        case .playerGestures: PlayerGestureSettingsView()
        case .playerChrome: PlayerChromeSettingsView()
        case .scrolling: InteractionSettingsView()
        case .account: AccountSettingsView()
        case .about: AboutSettingsView()
        case .diagnostics: RecommendationDiagnosticsView()
        }
    }
}
