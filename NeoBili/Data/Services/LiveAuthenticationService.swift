#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation

extension AuthenticationService {
    static var live: Self { live(session: AppNetwork.session, identity: .shared) }

    static func live(session: URLSession, identity: DeviceIdentity) -> Self {
        let transport = SMSPassport.liveTransport(session: session, identity: identity)
        return Self(encryptPassword: { try PasswordCipher.encryptedPassword($0, salt: $1, publicKeyPEM: $2) },
            generateQRCodeOperation: {
                try await BiliPassport.generateQRCode(session: session)
            },
            pollQRCodeOperation: { qrcodeKey in
                try await BiliPassport.pollQRCode(qrcodeKey, session: session)
            },
            generateAppQRCodeOperation: {
                try await BiliPassport.generateAppQRCode(session: session)
            },
            pollAppQRCodeOperation: { authCode, fallbackCookies in
                try await BiliPassport.pollAppQRCode(authCode, fallbackCookies: fallbackCookies, session: session)
            },
            webKeyOperation: {
                try await BiliPassport.webKey(session: session)
            },
            captchaOperation: {
                try await BiliPassport.captcha(session: session)
            },
            passwordLoginOperation: { username, passwordEncrypted, captchaToken, challenge, validate, seccode in
                try await BiliPassport.passwordLogin(username: username, passwordEncrypted: passwordEncrypted, captchaToken: captchaToken, challenge: challenge, validate: validate, seccode: seccode, session: session)
            },
            prepareOperation: {
                try await SMSPassport.prepare(identity: identity)
            },
            countriesOperation: {
                try await SMSPassport.countries(transport: transport)
            },
            sendOperation: { context, phone, country, captcha, result in
                try await SMSPassport.send(context: context, phone: phone, country: country, captcha: captcha, result: result, transport: transport)
            },
            loginOperation: { context, phone, country, code, key in
                try await SMSPassport.login(context: context, phone: phone, country: country, code: code, key: key, transport: transport)
            },
            exchangeOperation: { context, code in
                try await SMSPassport.exchange(context: context, code: code, transport: transport)
            },
            securityRequestOperation: { url, method, body, context in
                try SMSPassport.securityRequest(url: url, method: method, body: body, context: context)
            }
        )
    }
}
