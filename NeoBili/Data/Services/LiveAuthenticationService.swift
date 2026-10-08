import Foundation

extension AuthenticationService {
    static let live = Self(encryptPassword: { try PasswordCipher.encryptedPassword($0, salt: $1, publicKeyPEM: $2) },
        generateQRCodeOperation: {
            try await BiliPassport.generateQRCode()
        },
        pollQRCodeOperation: { qrcodeKey in
            try await BiliPassport.pollQRCode(qrcodeKey)
        },
        generateAppQRCodeOperation: {
            try await BiliPassport.generateAppQRCode()
        },
        pollAppQRCodeOperation: { authCode, fallbackCookies in
            try await BiliPassport.pollAppQRCode(authCode, fallbackCookies: fallbackCookies)
        },
        webKeyOperation: {
            try await BiliPassport.webKey()
        },
        captchaOperation: {
            try await BiliPassport.captcha()
        },
        passwordLoginOperation: { username, passwordEncrypted, captchaToken, challenge, validate, seccode in
            try await BiliPassport.passwordLogin(username: username, passwordEncrypted: passwordEncrypted, captchaToken: captchaToken, challenge: challenge, validate: validate, seccode: seccode)
        },
        prepareOperation: {
            try await SMSPassport.prepare()
        },
        countriesOperation: {
            try await SMSPassport.countries()
        },
        sendOperation: { context, phone, country, captcha, result in
            try await SMSPassport.send(context: context, phone: phone, country: country, captcha: captcha, result: result)
        },
        loginOperation: { context, phone, country, code, key in
            try await SMSPassport.login(context: context, phone: phone, country: country, code: code, key: key)
        },
        exchangeOperation: { context, code in
            try await SMSPassport.exchange(context: context, code: code)
        },
        securityRequestOperation: { url, method, body, context in
            try SMSPassport.securityRequest(url: url, method: method, body: body, context: context)
        }
    )
}
