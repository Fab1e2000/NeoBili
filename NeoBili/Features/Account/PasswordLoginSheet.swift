import SwiftUI

/// 账号密码登录。B 站网页端登录必须先过一次极验滑块，所以流程是：
/// 取公钥加密密码 → 取极验参数 → 弹滑块 → 提交登录。
struct PasswordLoginSheet: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var loginTask: Task<Void, Never>?
    @State private var expectedSession: UUID?
    @State private var statusText: String?
    @State private var errorMessage: String?
    /// 非 nil 时弹出滑块验证 sheet。
    @State private var geetestRequest: GeetestRequest?

    struct GeetestRequest: Identifiable {
        let gt: String
        let challenge: String
        let captchaToken: String
        let encryptedPassword: String
        let username: String

        var id: String { challenge }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("用户名 / 手机号 / 邮箱", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                    SecureField("密码", text: $password)
                }
                Section {
                    Button(action: { loginTask = Task { await startLogin() } }) {
                        HStack {
                            Spacer()
                            Text("登录").fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(username.isEmpty || password.isEmpty || isSubmitting)
                }
                if let statusText {
                    Section { Text(statusText).font(.footnote).foregroundStyle(.secondary) }
                }
                if let errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                }
                Section {
                    Text("第三方客户端无法绕过 B 站的风控，登录时需要完成一次滑块验证；多次失败可能触发账号保护，请稍后再试。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .navigationTitle("账号密码登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { loginTask?.cancel(); dismiss() }
                }
            }
            .sheet(item: $geetestRequest, onDismiss: {
                // A swipe dismissal has no Geetest callback. A submit task keeps the form busy.
                if loginTask == nil { isSubmitting = false; statusText = nil }
            }) { request in
                geetestSheet(request).appTextSize()
            }
            .onDisappear { loginTask?.cancel() }
        }
    }

    private func geetestSheet(_ request: GeetestRequest) -> some View {
        NavigationStack {
            GeetestView(gt: request.gt, challenge: request.challenge) { result in
                geetestRequest = nil
                guard let result else {
                    isSubmitting = false
                    statusText = nil
                    return
                }
                loginTask = Task { await submitLogin(request: request, result: result) }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("安全验证")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func startLogin() async {
        guard !isSubmitting else { return }
        expectedSession = account.sessionID
        let submittedUsername = username
        let submittedPassword = password
        isSubmitting = true
        errorMessage = nil
        statusText = nil
        defer { loginTask = nil; if geetestRequest == nil { isSubmitting = false } }
        do {
            let key = try await BiliPassport.webKey()
            try validateAttempt()
            let encrypted = try PasswordCipher.encryptedPassword(submittedPassword, salt: key.hash, publicKeyPEM: key.key)
            statusText = nil
            let captcha = try await BiliPassport.captcha()
            try validateAttempt()
            guard !captcha.gt.isEmpty, !captcha.challenge.isEmpty else {
                // 服务端没下发极验（少见）；直接不带验证提交，失败会显示原话。
                statusText = nil
                let cookies = try await BiliPassport.passwordLogin(
                    username: submittedUsername,
                    passwordEncrypted: encrypted,
                    captchaToken: captcha.token,
                    challenge: "",
                    validate: "",
                    seccode: ""
                )
                statusText = nil
                try validateAttempt()
                await account.completeLogin(cookies)
                dismiss()
                return
            }
            statusText = nil
            geetestRequest = GeetestRequest(
                gt: captcha.gt,
                challenge: captcha.challenge,
                captchaToken: captcha.token,
                encryptedPassword: encrypted,
                username: submittedUsername
            )
        } catch {
            guard !error.isCancellation, !Task.isCancelled else { return }
            statusText = nil
            errorMessage = BiliPassport.failureText(for: error)
        }
    }

    private func submitLogin(request: GeetestRequest, result: GeetestView.Result) async {
        isSubmitting = true
        statusText = nil
        defer { loginTask = nil; isSubmitting = false }
        do {
            try validateAttempt()
            let cookies = try await BiliPassport.passwordLogin(
                username: request.username,
                passwordEncrypted: request.encryptedPassword,
                captchaToken: request.captchaToken,
                challenge: result.challenge,
                validate: result.validate,
                seccode: result.seccode
            )
            statusText = nil
            try validateAttempt()
            await account.completeLogin(cookies)
            dismiss()
        } catch {
            guard !error.isCancellation, !Task.isCancelled else { return }
            statusText = nil
            errorMessage = BiliPassport.failureText(for: error)
        }
    }

    private func validateAttempt() throws {
        guard !Task.isCancelled, expectedSession == account.sessionID else { throw CancellationError() }
    }
}
