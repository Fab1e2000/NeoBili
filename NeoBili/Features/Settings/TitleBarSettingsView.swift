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
            } footer: {
                Text("随内容滚动时，标题随页面滚走；固定时可选择边界清晰的切边背景或柔和的渐变背景。搜索框始终保留在顶部。关注和直播始终使用固定切边导航栏，不受此设置影响。")
            }
        }
        .settingsPage("标题栏")
    }
}
