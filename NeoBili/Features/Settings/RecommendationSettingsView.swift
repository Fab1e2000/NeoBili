import SwiftUI

/// 首页推荐的数据来源、授权状态和刷新行为。
struct RecommendationSettingsView: View {
    @Environment(AccountStore.self) private var account
    /// 设置页盖在主界面之上，全局提示条看不到，失败原因直接写在分组说明里。
    @State private var credentialError: String?
    @State private var showsAppAuthorization = false
    @AppStorage(RecommendationFilter.appRecommendKey) private var usesAppRecommendation = true
    @AppStorage(RecommendationFilter.keepLastDataKey) private var keepsLastData = true
    @AppStorage(RecommendationFilter.lastSeenTipKey) private var showsLastSeenTip = true

    var body: some View {
        Form {
            Section {
                Toggle("首页使用 App 端推荐", isOn: $usesAppRecommendation)
                if account.isLoggedIn { appCredentialRow }
            } footer: {
                Text(appCredentialFooter)
            }

            Section {
                Toggle("刷新后保留上次数据", isOn: $keepsLastData)
                Toggle("显示上次看到位置提示", isOn: $showsLastSeenTip)
                    .disabled(!keepsLastData)
            } footer: {
                Text("开启后，新推荐后面保留旧卡片；关闭后，下次刷新会替换整个列表。默认开启。")
            }

            Section {
                NavigationLink("推荐内容过滤") { RecommendationFilterSettingsView() }
            }

        }
        .settingsPage("推荐流")
        .sheet(isPresented: $showsAppAuthorization) {
            SMSLoginSheet(appAuthorizationOnly: true)
        }
    }

    /// App 推荐要有 App 登录凭据才会按账号个性化；只有 Cookie 时可以在这里换一份。
    @ViewBuilder
    private var appCredentialRow: some View {
        if account.hasAppCredential {
            LabeledContent("App 登录凭据", value: String(localized: "已获取"))
        } else {
            LabeledContent("App 登录凭据") {
                if account.isExchangingAppCredential {
                    ProgressView()
                } else {
                    VStack(alignment: .trailing, spacing: 8) {
                        Button("验证码授权") { showsAppAuthorization = true }
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var appCredentialFooter: String {
        let base = String(localized: "关闭后改用网页端推荐。若网页端推荐不太符合预期，可切换回 App 端推荐。")
        guard account.isLoggedIn, !account.hasAppCredential else { return base }
        if account.needsAppReauthorization {
            return base + String(localized: "App 登录凭据已失效，请使用当前账号的短信验证码重新授权。网页登录状态已保留。")
        }
        let hint = base + String(localized: "当前账号还没有 App 登录凭据，App 端推荐会暂停并提示授权，不会静默切换为访客。请使用当前账号的短信验证码重新授权。")
        guard let credentialError = credentialError ?? account.appCredentialError else { return hint }
        return hint + "\n" + String(localized: "获取失败：\(credentialError)")
    }

}
