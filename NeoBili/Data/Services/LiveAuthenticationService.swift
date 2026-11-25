import NeoBiliDomain
import Foundation

extension AuthenticationService {

    public static func live(session: URLSession, identity: DeviceIdentity) -> Self {
        let transport = SMSPassport.liveTransport(session: session, identity: identity)
        return Self(
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
