import SwiftUI

/// 账号密码登录。B 站网页端登录必须先过一次极验滑块，所以流程是：
/// 取公钥加密密码 → 取极验参数 → 弹滑块 → 提交登录。
struct PasswordLoginSheet: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var statusText: String?
    @State private var errorMessage: String?
    /// 非 nil 时弹出滑块验证 sheet。
    @State private var geetestRequest: GeetestRequest?

    struct GeetestRequest: Identifiable {
        let gt: String
        let challenge: String
        let captchaToken: String
        let encryptedPassword: String

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
                    Button(action: { Task { await startLogin() } }) {
                        HStack {
                            Spacer()
                            if isSubmitting {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("登录").fontWeight(.semibold)
                            }
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
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(item: $geetestRequest) { request in
                geetestSheet(request)
            }
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
                Task { await submitLogin(request: request, result: result) }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("安全验证")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func startLogin() async {
        isSubmitting = true
        errorMessage = nil
        statusText = "正在获取登录密钥…"
        defer { if geetestRequest == nil { isSubmitting = false } }
        do {
            let key = try await BiliPassport.webKey()
            let encrypted = try PasswordCipher.encryptedPassword(password, salt: key.hash, publicKeyPEM: key.key)
            statusText = "正在准备安全验证…"
            let captcha = try await BiliPassport.captcha()
            guard !captcha.gt.isEmpty, !captcha.challenge.isEmpty else {
                // 服务端没下发极验（少见）；直接不带验证提交，失败会显示原话。
                statusText = "正在登录…"
                let cookies = try await BiliPassport.passwordLogin(
                    username: username,
                    passwordEncrypted: encrypted,
                    captchaToken: captcha.token,
                    challenge: "",
                    validate: "",
                    seccode: ""
                )
                statusText = nil
                await account.completeLogin(cookies)
                dismiss()
                return
            }
            statusText = nil
            geetestRequest = GeetestRequest(
                gt: captcha.gt,
                challenge: captcha.challenge,
                captchaToken: captcha.token,
                encryptedPassword: encrypted
            )
        } catch {
            statusText = nil
            errorMessage = error.localizedDescription
        }
    }

    private func submitLogin(request: GeetestRequest, result: GeetestView.Result) async {
        isSubmitting = true
        statusText = "正在登录…"
        defer { isSubmitting = false }
        do {
            let cookies = try await BiliPassport.passwordLogin(
                username: username,
                passwordEncrypted: request.encryptedPassword,
                captchaToken: request.captchaToken,
                challenge: result.challenge,
                validate: result.validate,
                seccode: result.seccode
            )
            statusText = nil
            await account.completeLogin(cookies)
            dismiss()
        } catch {
            statusText = nil
            errorMessage = error.localizedDescription
        }
    }
}
