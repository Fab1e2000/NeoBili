import SwiftUI

/// App token revocation is visible on entry while a valid web session is retained.
struct AppAuthorizationRecovery: ViewModifier {
    let account: AccountStore
    @State private var showsRevokedAuthorization = false
    @State private var showsAppAuthorization = false
    private var recoveryKind: Int {
        account.sessionExpired ? 2 : (account.needsAppReauthorization ? 1 : 0)
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: recoveryKind, initial: true) { _, kind in
                showsRevokedAuthorization = kind != 0
            }
            .alert(account.sessionExpired ? "登录已失效" : "App 登录授权已失效", isPresented: $showsRevokedAuthorization) {
                Button(account.sessionExpired ? "重新登录" : "重新授权") { showsAppAuthorization = true }
                Button("稍后", role: .cancel) {}
            } message: {
                if account.sessionExpired { Text("登录已失效，请重新登录。") }
                else { Text("App 登录授权已失效，请使用当前账号的短信验证码重新授权。网页登录状态已保留。") }
            }
            .sheet(isPresented: $showsAppAuthorization) {
                SMSLoginSheet(appAuthorizationOnly: account.isLoggedIn && account.needsAppReauthorization).appTextSize()
            }
            .onChange(of: account.sessionID) { showsAppAuthorization = false }
    }
}
