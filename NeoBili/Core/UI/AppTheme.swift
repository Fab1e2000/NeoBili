import SwiftUI

struct AppTheme: Identifiable {
    static let storageKey = "neobili.themeColor"
    static let defaultID = "pink"
    let id: String
    let name: String
    let hex: UInt32

    var color: Color {
        Color(red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255,
              blue: Double(hex & 255) / 255)
    }

    static func selected(_ id: String) -> AppTheme {
        presets.first { $0.id == id } ?? presets[0]
    }

    static let presets: [AppTheme] = [
        .init(id: "pink", name: String(localized: "樱花粉"), hex: 0xFB7AB3),
        .init(id: "rose", name: String(localized: "玫瑰红"), hex: 0xD94F78),
        .init(id: "ruby", name: String(localized: "宝石红"), hex: 0xC43C51),
        .init(id: "coral", name: String(localized: "珊瑚橙"), hex: 0xE66B58),
        .init(id: "orange", name: String(localized: "活力橙"), hex: 0xE77D22),
        .init(id: "amber", name: String(localized: "琥珀金"), hex: 0xBA871B),
        .init(id: "olive", name: String(localized: "橄榄绿"), hex: 0x879535),
        .init(id: "lime", name: String(localized: "青柠绿"), hex: 0x69A441),
        .init(id: "leaf", name: String(localized: "青草绿"), hex: 0x429961),
        .init(id: "forest", name: String(localized: "森林绿"), hex: 0x268260),
        .init(id: "jade", name: String(localized: "翡翠绿"), hex: 0x249B80),
        .init(id: "teal", name: String(localized: "青瓷色"), hex: 0x258E98),
        .init(id: "cyan", name: String(localized: "湖水蓝"), hex: 0x269DBD),
        .init(id: "sky", name: String(localized: "晴空蓝"), hex: 0x409DDA),
        .init(id: "blue", name: String(localized: "经典蓝"), hex: 0x3478D5),
        .init(id: "cobalt", name: String(localized: "钴蓝色"), hex: 0x4966C7),
        .init(id: "indigo", name: String(localized: "靛青色"), hex: 0x6860C7),
        .init(id: "violet", name: String(localized: "紫罗兰"), hex: 0x8A62C9),
        .init(id: "lavender", name: String(localized: "薰衣草"), hex: 0xA47CCB),
        .init(id: "orchid", name: String(localized: "兰花紫"), hex: 0xB561B4),
        .init(id: "berry", name: String(localized: "莓果色"), hex: 0xAC527F),
        .init(id: "cocoa", name: String(localized: "可可棕"), hex: 0x997159),
        .init(id: "slate", name: String(localized: "岩石蓝"), hex: 0x657F99),
        .init(id: "graphite", name: String(localized: "石墨灰"), hex: 0x7C8087)
    ]
}

private struct AppThemeModifier: ViewModifier {
    @AppStorage(AppTheme.storageKey) private var themeID = AppTheme.defaultID
    func body(content: Content) -> some View {
        let color = AppTheme.selected(themeID).color
        // Explicit accent-colored artwork keeps the theme; standard controls
        // use adaptive label color, including navigation buttons and close icons.
        content.environment(\.appThemeColor, color).accentColor(color).tint(.primary)
    }
}

extension View {
    func appTheme() -> some View { modifier(AppThemeModifier()) }
}

extension EnvironmentValues {
    @Entry var appThemeColor: Color = AppTheme.selected(AppTheme.defaultID).color
}
