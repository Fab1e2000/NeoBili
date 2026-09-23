import SwiftUI

struct AccountSettingsView: View {
    @Environment(AccountStore.self) private var account
    @State private var confirmLogout = false

    var body: some View {
        Form {
            Section {
                if let profile = account.profile {
                    LabeledContent("当前用户", value: profile.name)
                    LabeledContent("UID", value: String(profile.mid))
                }
                Button("退出登录", role: .destructive) { confirmLogout = true }
                    .disabled(!account.isLoggedIn)
            }
        }
        .settingsPage("账号管理")
        .confirmationDialog("确定退出登录？", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { Task { await account.logout() } }
            Button("取消", role: .cancel, action: {})
        }
    }
}
