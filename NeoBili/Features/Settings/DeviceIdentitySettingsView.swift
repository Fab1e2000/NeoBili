#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI

struct DeviceIdentitySettingsView: View {
    @Environment(\.applicationServices) private var services
    @AppStorage(DeviceIdentityPreferences.customKey) private var savedBuvid = ""
    @State private var input = ""
    @State private var currentBuvid = ""
    static let introductionSeenKey = "neobili.deviceIdentity.introductionSeen"
    @AppStorage(introductionSeenKey) private var hasSeenIntroduction = false
    @State private var activeAlert: DeviceIdentityAlert?

    private enum DeviceIdentityAlert { case introduction, saved }

    private var trimmed: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var valid: Bool { trimmed.isEmpty || DeviceIdentityPreferences.normalizedCustomBuvid(input) != nil }

    var body: some View {
        Form {
            Section {
                TextField("输入 BUVID，留空使用随机编号", text: $input, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("settings.deviceIdentity.input")
                Button("保存") {
                    savedBuvid = trimmed
                    input = trimmed
                    activeAlert = .saved
                }
                .disabled(!valid || trimmed == savedBuvid)
                .accessibilityIdentifier("settings.deviceIdentity.save")
                if !valid {
                    Text("BUVID 需为 16–128 位字母、数字或连字符")
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("留空使用默认编号，保存后重新打开应用生效。")
            }
            Section("当前使用的 BUVID") {
                Text(currentBuvid.isEmpty ? "—" : currentBuvid)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .accessibilityIdentifier("settings.deviceIdentity.current")
            }
        }
        .settingsPage("设备编号")
        .onAppear {
            input = savedBuvid
            if !hasSeenIntroduction { activeAlert = .introduction }
        }
        .task { currentBuvid = await services.currentAppBuvid() }
        .alert(activeAlert == .introduction ? "设备编号与推荐" : "已保存", isPresented: Binding(
            get: { activeAlert != nil },
            set: { if !$0 { activeAlert = nil } }
        )) {
            if activeAlert == .introduction {
                Button("知道了") { hasSeenIntroduction = true }
            } else {
                Button("好", role: .cancel) {}
            }
        } message: {
            if activeAlert == .introduction {
                Text("设备编号（BUVID）可能影响推荐流。想尝试让推荐更接近官方 App，可通过抓包查看自己官方 App 请求头中的 buvid，复制后在此填写并保存，再退出并重新打开 NeoBili。仅使用自己的编号；使用相同编号也不能保证推荐完全一致。")
            } else {
                Text("退出并重新打开 App 后生效")
            }
        }
    }
}
