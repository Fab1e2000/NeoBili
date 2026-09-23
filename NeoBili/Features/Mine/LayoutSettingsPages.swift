import SwiftUI

/// 标签栏：调整直播 / 推荐 / 关注的顺序，并选择启动时打开的页面。
struct TabBarSettingsView: View {
    @AppStorage(MainTabSettings.orderKey) private var storedOrder = MainTabSettings.stored(MainTabSettings.defaultOrder)
    @AppStorage(MainTabSettings.launchKey) private var storedLaunch = MainTabSettings.defaultLaunch.rawValue

    private var order: [MainTab] { MainTabSettings.order(from: storedOrder) }

    var body: some View {
        Form {
            Section {
                ForEach(order) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                }
                .onMove { source, destination in
                    var updated = order
                    updated.move(fromOffsets: source, toOffset: destination)
                    storedOrder = MainTabSettings.stored(updated)
                }
                Label(MainTab.search.title, systemImage: MainTab.search.systemImage)
                    .foregroundStyle(.secondary)
                    .moveDisabled(true)
            } header: {
                Text("标签顺序")
            } footer: {
                Text("拖动右侧的把手调整顺序。搜索始终固定在标签栏末尾。")
            }

            Section {
                Picker("启动时打开", selection: $storedLaunch) {
                    ForEach(order) { tab in
                        Text(tab.title).tag(tab.rawValue)
                    }
                }
            } footer: {
                Text("下次打开 App 时生效。")
            }

            Section {
                Button("恢复默认") {
                    storedOrder = MainTabSettings.stored(MainTabSettings.defaultOrder)
                    storedLaunch = MainTabSettings.defaultLaunch.rawValue
                }
                .disabled(order == MainTabSettings.defaultOrder
                          && MainTabSettings.launchTab(from: storedLaunch) == MainTabSettings.defaultLaunch)
            }
        }
        // 排序把手常驻，不需要先点「编辑」。
        .environment(\.editMode, .constant(.active))
        .settingsPage("标签栏")
    }
}

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
                     ? "标题和头像固定在顶部，卡片从下方滑过，边缘清晰，与直播、关注页一致。"
                     : "标题和头像随卡片一起滚走，顶部只在状态栏处柔和渐隐。")
            }
        }
        .settingsPage("推荐页")
    }
}

extension HomeTitleBarSettings {
    static func summary(pinned: Bool) -> String { pinned ? "固定标题栏" : "滚动标题栏" }
}
