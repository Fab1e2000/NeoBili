import SwiftUI

/// Stable destination IDs also identify rows to accessibility and regression tests.
enum SettingsDestination: String, CaseIterable, Identifiable {
    case theme, display, language, cardAnimations
    case tabBar, titleBar, contentFilter, recommendation, scrolling
    case playback, danmaku, playerGestures, playerChrome
    case account, deviceIdentity, diagnostics, about
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .theme: "主题色"
        case .display: "文字大小"
        case .language: "语言"
        case .cardAnimations: "动画"
        case .tabBar: "标签栏"
        case .titleBar: "标题栏"
        case .contentFilter: "内容过滤"
        case .recommendation: "推荐流"
        case .scrolling: "滚动与防误触"
        case .playback: "播放与画质"
        case .danmaku: "弹幕"
        case .playerGestures: "播放器手势"
        case .playerChrome: "播放器控件位置"
        case .account: "账号管理"
        case .deviceIdentity: "设备编号"
        case .diagnostics: "推荐实验日志"
        case .about: "关于"
        }
    }
}

enum SettingsCategory: String, CaseIterable, Identifiable {
    case appearance, browsing, playback, account, advanced, information
    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .appearance: "外观"
        case .browsing: "浏览"
        case .playback: "播放"
        case .account: "账号"
        case .advanced: "高级"
        case .information: "关于"
        }
    }
    var destinations: [SettingsDestination] {
        switch self {
        case .appearance: [.theme, .display, .language, .cardAnimations]
        case .browsing: [.tabBar, .titleBar, .contentFilter, .recommendation, .scrolling]
        case .playback: [.playback, .danmaku, .playerGestures, .playerChrome]
        case .account: [.account]
        case .advanced:
            #if DEBUG
            [.deviceIdentity, .diagnostics]
            #else
            [.deviceIdentity]
            #endif
        case .information: [.about]
        }
    }
}
