import SwiftUI

struct SMSLoginSheet: View {
    @Environment(\.applicationServices) private var services
    var appAuthorizationOnly = false
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var model = SMSLoginModel()
    @State private var expectedSession = UUID()
    @State private var completionError: String?
    @FocusState private var focusedField: Field?
    private enum Field { case phone, code }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Picker("国家或地区", selection: $model.country) {
                        ForEach(model.countries) { country in
                            Text("\(country.cname) +\(country.countryId)").tag(country.id)
                        }
                    }
                    TextField("手机号", text: $model.phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .focused($focusedField, equals: .phone)
                        .accessibilityIdentifier("sms.phone")
                    TextField("短信验证码", text: $model.code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($focusedField, equals: .code)
                        .accessibilityIdentifier("sms.code")
                }
                .disabled(model.busy || model.credentials != nil)
                Section {
                    TimelineView(.periodic(from: .now, by: 1)) { time in
                        let remaining = max(0, Int(ceil(model.resendAt.timeIntervalSince(time.date))))
                        Button(remaining > 0 ? String(localized: "\(remaining) 秒后重新获取") : String(localized: "获取验证码")) {
                            focusedField = nil
                            Task { await model.sendCode() }
                        }
                        .disabled(!model.validPhone || model.busy || remaining > 0 || model.credentials != nil)
                        .accessibilityIdentifier("sms.send")
                    }
                    Button("登录") {
                        focusedField = nil
                        Task { await model.submit() }
                    }
                    .disabled(!model.canLogin || model.credentials != nil)
                    .accessibilityIdentifier("sms.login")
                }
                if model.busy { Section { HStack { ProgressView(); Text("正在处理") } } }
                if model.sent { Section { Text("验证码已发送，请在五分钟内填写。") } }
                if let error = completionError ?? model.error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                if appAuthorizationOnly {
                    Section { Text("请使用当前账号绑定的手机号完成验证。") }
                }
            }
            .navigationTitle("短信验证码登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { model.cancel(); dismiss() }
                }
            }
            .task {
                expectedSession = account.sessionID
                await model.loadCountries()
            }
            .onChange(of: model.phone) { model.resetPhone(); completionError = nil }
            .onChange(of: model.country) { model.resetPhone(); completionError = nil }
            .task(id: model.credentials) {
                guard let value = model.credentials else { return }
                do {
                    guard account.sessionID == expectedSession,
                          model.preparedAccountSession == services.session.currentID(), !Task.isCancelled else { throw CancellationError() }
                    guard let identitySession = model.preparedAccountSession else { throw CancellationError() }
                    try await account.completeSMSLogin(value, expectedSessionID: expectedSession,
                        expectedIdentitySession: identitySession, authorizationOnly: appAuthorizationOnly)
                    if !Task.isCancelled { dismiss() }
                } catch {
                    completionError = LoginModels.failureText(for: error)
                }
            }
            .sheet(item: $model.captcha) { challenge in
                NavigationStack {
                    GeetestView(gt: challenge.gt, challenge: challenge.challenge) { result in
                        model.captcha = nil
                        guard let result else { return }
                        Task { await model.sendCode(result: .init(challenge: result.challenge, validate: result.validate, seccode: result.seccode), challenge: challenge) }
                    }
                    .navigationTitle("安全验证")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { model.captcha = nil } } }
                }
                .appTextSize()
            }
            .sheet(item: $model.verification) { verification in
                NavigationStack {
                    SMSSecurityView(url: verification.url, loginContext: verification.context) { code in
                        Task { await model.completeVerification(code) }
                    } onError: {
                        completionError = String(localized: "安全验证页面无法加载，请关闭后重试")
                    }
                    .navigationTitle("安全验证")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { model.verification = nil } } }
                }
                .appTextSize()
            }
            .onDisappear { model.cancel() }
        }
    }
}
