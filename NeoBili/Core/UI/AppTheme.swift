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
        .init(id: "pink", name: "樱花粉", hex: 0xFB7AB3),
        .init(id: "rose", name: "玫瑰红", hex: 0xD94F78),
        .init(id: "ruby", name: "宝石红", hex: 0xC43C51),
        .init(id: "coral", name: "珊瑚橙", hex: 0xE66B58),
        .init(id: "orange", name: "活力橙", hex: 0xE77D22),
        .init(id: "amber", name: "琥珀金", hex: 0xBA871B),
        .init(id: "olive", name: "橄榄绿", hex: 0x879535),
        .init(id: "lime", name: "青柠绿", hex: 0x69A441),
        .init(id: "leaf", name: "青草绿", hex: 0x429961),
        .init(id: "forest", name: "森林绿", hex: 0x268260),
        .init(id: "jade", name: "翡翠绿", hex: 0x249B80),
        .init(id: "teal", name: "青瓷色", hex: 0x258E98),
        .init(id: "cyan", name: "湖水蓝", hex: 0x269DBD),
        .init(id: "sky", name: "晴空蓝", hex: 0x409DDA),
        .init(id: "blue", name: "经典蓝", hex: 0x3478D5),
        .init(id: "cobalt", name: "钴蓝色", hex: 0x4966C7),
        .init(id: "indigo", name: "靛青色", hex: 0x6860C7),
        .init(id: "violet", name: "紫罗兰", hex: 0x8A62C9),
        .init(id: "lavender", name: "薰衣草", hex: 0xA47CCB),
        .init(id: "orchid", name: "兰花紫", hex: 0xB561B4),
        .init(id: "berry", name: "莓果色", hex: 0xAC527F),
        .init(id: "cocoa", name: "可可棕", hex: 0x997159),
        .init(id: "slate", name: "岩石蓝", hex: 0x657F99),
        .init(id: "graphite", name: "石墨灰", hex: 0x7C8087)
    ]
}

private struct AppThemeModifier: ViewModifier {
    @AppStorage(AppTheme.storageKey) private var themeID = AppTheme.defaultID
    func body(content: Content) -> some View {
        let color = AppTheme.selected(themeID).color
        content.tint(color).accentColor(color)
    }
}

extension View {
    func appTheme() -> some View { modifier(AppThemeModifier()) }
}
