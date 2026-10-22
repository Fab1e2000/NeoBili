import SwiftUI

/// 标题栏样式；关注和直播保留固定切边导航栏。
struct TitleBarSettingsView: View {
    @TitleBarPreference private var style

    var body: some View {
        Form {
            Section {
                Picker("标题栏", selection: $style) {
                    ForEach(TitleBarSettings.Style.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
        .settingsPage("标题栏")
    }
}
