import SwiftUI

/// 推荐页的外观：标题栏的两套实现。
struct HomePageSettingsView: View {
    @AppStorage(HomeTitleBarSettings.storageKey) private var pinsTitleBar = HomeTitleBarSettings.defaultValue

    var body: some View {
        Form {
            Section {
                Picker("标题栏", selection: $pinsTitleBar) {
                    Text("随内容滚动").tag(false)
                    Text("固定在顶部").tag(true)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("标题栏")
            } footer: {
                Text(pinsTitleBar
                     ? "标题和头像固定在顶部，卡片从下方滑过，与直播、关注等页面一致。"
                     : "标题和头像随卡片一起滚走，顶部只在状态栏处柔和渐隐。")
            }
        }
        .settingsPage("推荐页")
    }
}

extension HomeTitleBarSettings {
    static func summary(pinned: Bool) -> String { pinned ? "固定标题栏" : "滚动标题栏" }
}
