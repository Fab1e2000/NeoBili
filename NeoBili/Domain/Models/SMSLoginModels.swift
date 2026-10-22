import Foundation

public enum SMSLoginModels {
    public struct Context: Sendable {
        public let accountSession: UUID
        public let headers: [String: String]
        public let buvid: String
        public let deviceID: String
        public let loginSession: String

        public init(
            accountSession: UUID,
            headers: [String: String],
            buvid: String,
            deviceID: String,
            loginSession: String
        ) {
            self.accountSession = accountSession
            self.headers = headers
            self.buvid = buvid
            self.deviceID = deviceID
            self.loginSession = loginSession
        }
    }

    public struct Country: Decodable, Identifiable, Hashable, Sendable {
        public let id: Int
        public let cname: String
        public let countryId: String
        enum CodingKeys: String, CodingKey { case id, cname; case countryId = "country_id" }

        public init(
            id: Int,
            cname: String,
            countryId: String
        ) {
            self.id = id
            self.cname = cname
            self.countryId = countryId
        }
    }

    public struct Captcha: Identifiable, Sendable {
        public let token: String
        public let gt: String
        public let challenge: String
        public var id: String { challenge }

        public init(
            token: String,
            gt: String,
            challenge: String
        ) {
            self.token = token
            self.gt = gt
            self.challenge = challenge
        }
    }

    public struct ChallengeResult: Sendable {
        public let challenge: String
        public let validate: String
        public let seccode: String

        public init(
            challenge: String,
            validate: String,
            seccode: String
        ) {
            self.challenge = challenge
            self.validate = validate
            self.seccode = seccode
        }
    }

    public enum SendOutcome: Sendable { case sent(String); case captcha(Captcha) }

    public struct Credentials: Codable, Equatable, Sendable {
        public let cookies: LoginModels.LoginCookies
        public let accessKey: String
        public var refreshToken: String? = nil
        public var expiresIn: Int? = nil

        public init(
            cookies: LoginModels.LoginCookies,
            accessKey: String,
            refreshToken: String? = nil,
            expiresIn: Int? = nil
        ) {
            self.cookies = cookies
            self.accessKey = accessKey
            self.refreshToken = refreshToken
            self.expiresIn = expiresIn
        }
    }

    public enum LoginOutcome: Sendable { case confirmed(Credentials); case verification(URL) }
}
