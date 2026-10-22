#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI

/// 首页推荐的数据来源、授权状态和刷新行为。
struct RecommendationSettingsView: View {
    @Environment(AccountStore.self) private var account
    /// 设置页盖在主界面之上，全局提示条看不到，失败原因直接写在分组说明里。
    @State private var credentialError: String?
    @State private var showsAppAuthorization = false
    @AppStorage(RecommendationRequest.sourceKey) private var savedSource = ""
    @AppStorage(RecommendationFilter.appRecommendKey) private var legacyUsesApp = true
    private var source: Binding<RecommendationRequest.Source> {
        Binding(get: { RecommendationRequest.savedSource(rawValue: savedSource, legacyUsesApp: legacyUsesApp) },
                set: { savedSource = $0.rawValue })
    }
    @AppStorage(RecommendationFilter.keepLastDataKey) private var keepsLastData = true
    @AppStorage(RecommendationFilter.lastSeenTipKey) private var showsLastSeenTip = true

    var body: some View {
        Form {
            Section {
                Picker(selection: source) {
                    Text("移动端推荐").tag(RecommendationRequest.Source.app)
                    Text("网页推荐").tag(RecommendationRequest.Source.web)
                    Text("混合推荐").tag(RecommendationRequest.Source.merged)
                } label: { Text("推荐来源") }
                if account.isLoggedIn { appCredentialRow }
            } footer: {
                Text(appCredentialFooter)
            }

            Section {
                Toggle("刷新后保留上次数据", isOn: $keepsLastData)
                Toggle("显示上次看到位置提示", isOn: $showsLastSeenTip)
                    .disabled(!keepsLastData)
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
        let base = String(localized: "切换后重新打开应用生效。")
        guard account.isLoggedIn, !account.hasAppCredential else { return base }
        if account.needsAppReauthorization {
            return base + String(localized: "App 授权已失效，请重新授权。")
        }
        let hint = base + String(localized: "移动端推荐需要当前账号的验证码授权。")
        guard let credentialError = credentialError ?? account.appCredentialError else { return hint }
        return hint + "\n" + String(localized: "获取失败：\(credentialError)")
    }

}
