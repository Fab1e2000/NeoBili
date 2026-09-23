import SwiftUI

struct FollowingSettingsView: View {
    @AppStorage(FollowingSidebarSide.storageKey) private var side: FollowingSidebarSide = .left
    @AppStorage(FollowingSidebarLayout.countKey) private var count = FollowingSidebarLayout.defaultCount
    @AppStorage(FollowingSidebarDwellSettings.storageKey) private var dwellDuration = FollowingSidebarDwellSettings.defaultDuration

    var body: some View {
        Form {
            Section("选择器") {
                Picker("头像列表位置", selection: $side) {
                    ForEach(FollowingSidebarSide.allCases) { side in
                        Text(side.title).tag(side)
                    }
                }
                Picker("显示数量", selection: $count) {
                    ForEach(FollowingSidebarLayout.counts, id: \.self) { count in
                        Text("\(count) 个").tag(count)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("停留判定时间", value: String(format: "%.1f 秒", FollowingSidebarDwellSettings.clamped(dwellDuration)))
                        .monospacedDigit()
                    Slider(value: $dwellDuration, in: FollowingSidebarDwellSettings.range, step: 0.1)
                        .accessibilityLabel("头像停留判定时间")
                        .accessibilityValue("\(FollowingSidebarDwellSettings.clamped(dwellDuration), specifier: "%.1f") 秒")
                }
            }
        }
        .settingsPage("关注页")
    }
}
