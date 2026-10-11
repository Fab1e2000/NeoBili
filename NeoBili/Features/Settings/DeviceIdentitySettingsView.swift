import SwiftUI

struct DeviceIdentitySettingsView: View {
    @Environment(\.applicationServices) private var services
    @AppStorage(DeviceIdentityPreferences.customKey) private var savedBuvid = ""
    @State private var input = ""
    @State private var currentBuvid = ""
    @State private var saved = false

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
                    saved = true
                }
                .disabled(!valid || trimmed == savedBuvid)
                .accessibilityIdentifier("settings.deviceIdentity.save")
                if !valid {
                    Text("BUVID 需为 16–128 位字母、数字或连字符")
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("填写后保存并持续使用。留空时随机生成一次，之后复用。保存后退出并重新打开 App 生效。")
            }
            Section("当前使用的 BUVID") {
                Text(currentBuvid.isEmpty ? "—" : currentBuvid)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .accessibilityIdentifier("settings.deviceIdentity.current")
            }
        }
        .settingsPage("设备编号")
        .onAppear { input = savedBuvid }
        .task { currentBuvid = await services.currentAppBuvid() }
        .alert("已保存", isPresented: $saved) {
            Button("好", role: .cancel) {}
        } message: {
            Text("退出并重新打开 App 后生效")
        }
    }
}
