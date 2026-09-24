import SwiftUI

/// 全局标题栏样式：所有主页面的标题和头像随内容滚动，或固定在顶部。
struct TitleBarSettingsView: View {
    @AppStorage(TitleBarSettings.storageKey) private var pinsTitleBar = TitleBarSettings.defaultValue

    var body: some View {
        Form {
            Section {
                Picker("标题栏", selection: $pinsTitleBar) {
                    Text("随内容滚动").tag(false)
                    Text("固定在顶部").tag(true)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text(pinsTitleBar
                     ? "各页面的标题和头像固定在顶部，内容从下方滑过。关注页的头像条、直播页的推荐/关注切换器与标题一起固定。"
                     : "各页面的标题和头像随内容一起滚走。关注页的头像条、直播页的推荐/关注切换器也随标题一起滚走；搜索页上滑时只收起标题，搜索框留在顶部。")
            }
        }
        .settingsPage("标题栏")
    }
}
