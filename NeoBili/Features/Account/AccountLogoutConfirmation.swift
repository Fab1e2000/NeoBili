import SwiftUI

/// All account exit points keep the session until the user confirms.
private struct AccountLogoutConfirmation: ViewModifier {
    @Environment(AccountStore.self) private var account
    @Binding var isPresented: Bool
    @State private var expectedSession: UUID?

    func body(content: Content) -> some View {
        content
            .confirmationDialog("确定退出登录？", isPresented: $isPresented, titleVisibility: .visible) {
                Button("退出登录", role: .destructive) {
                    guard let expectedSession, account.sessionID == expectedSession else { return }
                    Task {
                        guard account.sessionID == expectedSession else { return }
                        await account.logout()
                    }
                }
                Button("取消", role: .cancel, action: {})
            }
            .onChange(of: isPresented) {
                expectedSession = isPresented ? account.sessionID : nil
            }
            .onChange(of: account.sessionID) {
                isPresented = false
                expectedSession = nil
            }
    }
}

extension View {
    func accountLogoutConfirmation(isPresented: Binding<Bool>) -> some View {
        modifier(AccountLogoutConfirmation(isPresented: isPresented))
    }
}
