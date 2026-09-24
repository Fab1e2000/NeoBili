import SwiftUI

/// 标签栏：调整顺序、隐藏不常用的标签，并选择启动时打开的页面。
struct TabBarSettingsView: View {
    @AppStorage(MainTabSettings.orderKey) private var storedOrder = MainTabSettings.stored(MainTabSettings.defaultOrder)
    @AppStorage(MainTabSettings.hiddenKey) private var storedHidden: String?
    @AppStorage(MainTabSettings.launchKey) private var storedLaunch = MainTabSettings.defaultLaunch.rawValue

    private var order: [MainTab] { MainTabSettings.order(from: storedOrder) }
    private var hidden: Set<MainTab> { MainTabSettings.effectiveHidden(order: storedOrder, hidden: storedHidden) }
    private var shown: [MainTab] { order.filter { !hidden.contains($0) } }
    private var hiddenInOrder: [MainTab] { order.filter { hidden.contains($0) } }

    var body: some View {
        Form {
            Section {
                ForEach(shown) { tab in
                    HStack {
                        Label(tab.title, systemImage: tab.systemImage)
                        Spacer()
                        Button {
                            setHidden(tab, true)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                                .font(.title3)
                        }
                        .buttonStyle(.borderless)
                        // 至少保留一个标签。
                        .disabled(shown.count <= 1)
                        .accessibilityLabel("隐藏\(tab.title)")
                    }
                }
                .onMove(perform: moveShown)
                Label(MainTab.search.title, systemImage: MainTab.search.systemImage)
                    .foregroundStyle(.secondary)
                    .moveDisabled(true)
            } header: {
                Text("显示的标签")
            } footer: {
                Text(String(localized: "拖动右侧的把手调整顺序，点红色按钮隐藏。标签栏最多 \(MainTabSettings.maxVisible + 1) 个（含固定在末尾的搜索），不会出现「更多」。"))
            }

            if !hiddenInOrder.isEmpty {
                Section {
                    ForEach(hiddenInOrder) { tab in
                        HStack {
                            Label(tab.title, systemImage: tab.systemImage)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                setHidden(tab, false)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.title3)
                            }
                            .buttonStyle(.borderless)
                            // 已达上限时先隐藏一个再添加。
                            .disabled(shown.count >= MainTabSettings.maxVisible)
                            .accessibilityLabel("显示\(tab.title)")
                        }
                        .moveDisabled(true)
                    }
                } header: {
                    Text("隐藏的标签")
                } footer: {
                    if shown.count >= MainTabSettings.maxVisible {
                        Text("显示的标签已满，先隐藏一个才能添加。")
                    }
                }
            }

            Section {
                Picker("启动时打开", selection: Binding(
                    get: { MainTabSettings.launchTab(from: storedLaunch, visible: shown).rawValue },
                    set: { storedLaunch = $0 }
                )) {
                    ForEach(shown) { tab in
                        Text(tab.title).tag(tab.rawValue)
                    }
                }
            } footer: {
                Text("下次打开 App 时生效。")
            }

            Section {
                Button("恢复默认") {
                    storedOrder = MainTabSettings.stored(MainTabSettings.defaultOrder)
                    storedHidden = MainTabSettings.stored(MainTabSettings.defaultHidden)
                    storedLaunch = MainTabSettings.defaultLaunch.rawValue
                }
                .disabled(order == MainTabSettings.defaultOrder && hidden == MainTabSettings.defaultHidden
                          && MainTabSettings.launchTab(from: storedLaunch, visible: shown) == MainTabSettings.defaultLaunch)
            }
        }
        // 排序把手常驻，不需要先点「编辑」。
        .environment(\.editMode, .constant(.active))
        .settingsPage("标签栏")
    }

    /// 只在显示的标签之间拖动；隐藏的标签保持在原来的相对位置。
    private func moveShown(from source: IndexSet, to destination: Int) {
        var reordered = shown
        reordered.move(fromOffsets: source, toOffset: destination)
        var iterator = reordered.makeIterator()
        storedOrder = MainTabSettings.stored(order.map { hidden.contains($0) ? $0 : iterator.next()! })
    }

    private func setHidden(_ tab: MainTab, _ isHidden: Bool) {
        var updated = hidden
        if isHidden { updated.insert(tab) } else { updated.remove(tab) }
        withAnimation { storedHidden = MainTabSettings.stored(order.filter(updated.contains)) }
    }
}
