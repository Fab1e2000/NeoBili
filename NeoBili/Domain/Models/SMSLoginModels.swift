import Foundation

enum SMSLoginModels {
    struct Context: Sendable {
        let accountSession: UUID
        let headers: [String: String]
        let buvid: String
        let deviceID: String
        let loginSession: String
    }

    struct Country: Decodable, Identifiable, Hashable, Sendable {
        let id: Int
        let cname: String
        let countryId: String
        enum CodingKeys: String, CodingKey { case id, cname; case countryId = "country_id" }
    }

    struct Captcha: Identifiable, Sendable {
        let token: String
        let gt: String
        let challenge: String
        var id: String { challenge }
    }

    struct ChallengeResult: Sendable {
        let challenge: String
        let validate: String
        let seccode: String
    }

    enum SendOutcome: Sendable { case sent(String); case captcha(Captcha) }

    struct Credentials: Codable, Equatable, Sendable {
        let cookies: LoginModels.LoginCookies
        let accessKey: String
        var refreshToken: String? = nil
        var expiresIn: Int? = nil
    }

    enum LoginOutcome: Sendable { case confirmed(Credentials); case verification(URL) }
}
