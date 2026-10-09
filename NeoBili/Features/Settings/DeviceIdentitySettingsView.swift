import SwiftUI


struct DeviceIdentitySettingsView: View {
    @AppStorage(DeviceIdentityPreferences.modeKey) private var storedMode = DeviceIdentityPreferences.launchMode.rawValue

    private var selectedMode: DeviceIdentityPreferences.Mode { DeviceIdentityPreferences.Mode(rawValue: storedMode) ?? .system }

    var body: some View {
        Form {
            Section {
                Picker("编号生成方式", selection: Binding(get: { selectedMode.rawValue }, set: { storedMode = $0 })) {
                    ForEach(DeviceIdentityPreferences.Mode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .accessibilityIdentifier("settings.deviceIdentity.mode")
                LabeledContent("当前生效", value: DeviceIdentityPreferences.launchMode.title)
            } footer: {
                Text("两种编号均在本机生成并保存。系统派生模式沿用原编号；随机模式首次生成后持续复用，不会每次刷新都更换。")
            }
            Section {
                if selectedMode != DeviceIdentityPreferences.launchMode {
                    Label("退出并重新打开 App 后生效", systemImage: "arrow.clockwise")
                        .foregroundStyle(.secondary)
                }
                Text("切换会配套切换设备登记与票据，账号登录保持不变。可切回原模式恢复原编号。推荐结果可能变化，此功能用于兼容性测试。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .settingsPage("设备编号")
    }
}
