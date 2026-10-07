import SwiftUI

/// 与 PiliPlus「推荐流设置」相同的选项，只作用于首页推荐。
struct RecommendationSettingsView: View {
    @Environment(AccountStore.self) private var account
    /// 设置页盖在主界面之上，全局提示条看不到，失败原因直接写在分组说明里。
    @State private var credentialError: String?
    @State private var showsAppAuthorization = false
    @AppStorage(RecommendationFilter.appRecommendKey) private var usesAppRecommendation = true
    @AppStorage(RecommendationFilter.keepLastDataKey) private var keepsLastData = true
    @AppStorage(RecommendationFilter.lastSeenTipKey) private var showsLastSeenTip = true
    @AppStorage(RecommendationFilter.minLikeRatioKey) private var minLikeRatio = 0
    @AppStorage(RecommendationFilter.minDurationKey) private var minDuration = 0
    @AppStorage(RecommendationFilter.minPlayKey) private var minPlay = 0
    @AppStorage(RecommendationFilter.titleBanWordKey) private var titleBanWord = ""
    @AppStorage(RecommendationFilter.zoneBanWordKey) private var zoneBanWord = ""
    @AppStorage(RecommendationFilter.exemptFollowedKey) private var exemptsFollowed = true

    var body: some View {
        Form {
            #if DEBUG
            Section { NavigationLink("推荐实验日志") { RecommendationDiagnosticsView() } }
            #endif
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
                picker("点赞率", selection: $minLikeRatio, options: RecommendationFilter.likeRatioOptions) { "\($0)%" }
                picker("视频时长", selection: $minDuration, options: RecommendationFilter.durationOptions) {
                    String(localized: "\($0) 秒")
                }
                picker("播放量", selection: $minPlay, options: RecommendationFilter.playOptions) { "\($0)" }
                Toggle("已关注 UP 豁免推荐过滤", isOn: $exemptsFollowed)
            } header: {
                Text("过滤")
            } footer: {
                Text("低于所选值的推荐会被隐藏。已关注 UP 发布的内容可以不受这些条件和标题关键词影响。")
            }

            Section {
                TextField("标题关键词", text: $titleBanWord, axis: .vertical)
                TextField("分区关键词", text: $zoneBanWord, axis: .vertical)
            } header: {
                Text("关键词过滤")
            } footer: {
                Text("使用 | 隔开，如：尝试|测试。标题或分区名包含这些词的推荐会被隐藏；网页端推荐不提供分区名，分区关键词只对 App 端推荐生效。")
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
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

    /// 档位与 PiliPlus 相同；0 表示不过滤。
    private func picker(_ title: LocalizedStringKey, selection: Binding<Int>, options: [Int],
                        label: @escaping (Int) -> String) -> some View {
        Picker(title, selection: selection) {
            ForEach(options.contains(selection.wrappedValue) ? options : (options + [selection.wrappedValue]).sorted(),
                    id: \.self) { value in
                Text(value == 0 ? String(localized: "不限制") : label(value)).tag(value)
            }
        }
    }
}
