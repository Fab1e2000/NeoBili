import Foundation
import CryptoKit

/// Native passport flow traced in 8.89: info -> timestamp -> refresh -> persist -> confirm.
/// No timer, no automatic replay of token-rotating writes, and no production credentials in logs.
enum AppLoginRenewal {
    typealias Transport = SMSPassport.Transport
    struct Snapshot: Sendable {
        let session: UUID
        let credentials: SMSPassport.Credentials
    }
    struct Device: Sendable {
        let buvid: String
        let localID: String
        let deviceID: String
        let name: String
        let platform: String
        let headers: [String: String]
    }
    struct Info: Decodable, Sendable {
        let mid: Int
        let expires_in: Int
        let refresh: Bool
    }
    enum Failure: Error { case malformed, rejected(Int), wrongAccount, storage }

    static func request(_ path: String, old: SMSPassport.Credentials, device: Device,
                        fields: [String: String] = [:], post: Bool = false,
                        timestamp: Int = Int(Date().timeIntervalSince1970)) -> URLRequest {
        var parameters = AppClientIdentity.parameters.merging([
            "actionKey": "appkey", "statistics": AppClientIdentity.statistics,
            "c_locale": "zh-Hans_CN", "s_locale": "zh-Hans_CN", "disable_rcmd": "0",
            "sdk_ver": "0.1.15", "access_key": old.accessKey,
            "local_id": device.buvid, "buvid": device.buvid, "bili_local_id": device.localID,
            "device_id": device.deviceID, "device_name": device.name, "device_platform": device.platform
        ]) { _, new in new }
        parameters.merge(fields) { _, new in new }
        let encoded = AppSigner.queryString(from: AppSigner.signed(parameters, purpose: .passport, timestamp: timestamp, nativeEncoding: true), nativeEncoding: true)
        var url = URLComponents(string: "https://passport.bilibili.com/x/passport-login/" + path)!
        if !post { url.percentEncodedQuery = encoded }
        var request = URLRequest(url: url.url!)
        request.httpMethod = post ? "POST" : "GET"
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 15
        for (key, value) in device.headers { request.setValue(value, forHTTPHeaderField: key) }
        request.setValue(AppClientIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        // The old SSO's session is an explicit confirm form field, never the newly saved Cookie.
        if post {
            request.httpBody = Data(encoded.utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    static func object(_ request: URLRequest, transport: Transport) async throws -> [String: Any] {
        try Task.checkCancellation()
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = json["code"] as? NSNumber, CFGetTypeID(code) != CFBooleanGetTypeID() else { throw Failure.malformed }
        guard code.intValue == 0 else { throw Failure.rejected(code.intValue) }
        return json
    }

    static func info(old: SMSPassport.Credentials, device: Device, transport: Transport) async throws -> Info {
        let json = try await object(request("oauth2/info", old: old, device: device), transport: transport)
        guard let data = json["data"] as? [String: Any] else { throw Failure.malformed }
        let info = try JSONDecoder().decode(Info.self, from: JSONSerialization.data(withJSONObject: data))
        guard info.mid > 0, String(info.mid) == old.cookies.dedeUserID else { throw Failure.wrongAccount }
        guard info.expires_in > 0 else { throw Failure.malformed }
        return info
    }

    static func serverTime(old: SMSPassport.Credentials, device: Device, transport: Transport) async -> Int {
        // The official caller ignores a timestamp error and substitutes -1 for zero.
        guard let json = try? await object(request("timestamp", old: old, device: device), transport: transport),
              let data = json["data"] as? [String: Any], let time = data["timestamp"] as? NSNumber,
              CFGetTypeID(time) != CFBooleanGetTypeID(), time.intValue != 0 else { return -1 }
        return time.intValue
    }

    static func refresh(old: SMSPassport.Credentials, device: Device, sts: Int,
                        transport: Transport) async throws -> SMSPassport.Credentials {
        guard let token = old.refreshToken, !token.isEmpty else { throw Failure.malformed }
        let json = try await object(request("oauth2/refresh_token", old: old, device: device,
            fields: ["refresh_token": token, "sts": String(sts)], post: true), transport: transport)
        guard case .confirmed(let result) = try SMSPassport.loginOutcome(json),
              result.cookies.dedeUserID == old.cookies.dedeUserID,
              result.refreshToken?.isEmpty == false, (result.expiresIn ?? 0) > 0 else { throw Failure.malformed }
        return result
    }

    static func confirm(old: SMSPassport.Credentials, device: Device, sts: Int, transport: Transport) async throws {
        _ = try await object(request("confirm/refresh", old: old, device: device,
            fields: ["mid": old.cookies.dedeUserID, "session": old.cookies.sessdata,
                     "refresh_token": old.refreshToken ?? "", "revoke_api": "REFRESH_CONFIRM_REVOKE", "sts": String(sts)],
            post: true), transport: transport)
    }
}

/// Distinct from the tracking BUVID. 8.89 BFCDeviceToken.localBUVID/signBUVID.
enum AppLocalDeviceID {
    static func generate(vendor: String, platform: String, firstRun: Int64, date: Date,
                         timeZone: TimeZone = .current) -> String {
        func md5(_ text: String) -> String {
            Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02X", $0) }.joined()
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMddHHmmss"
        let body = md5(vendor + "+" + platform + "+Apple") + formatter.string(from: date)
            + md5("iOS+\(firstRun)").prefix(16)
        let bytes = Array(body.utf8)
        let checksum = stride(from: 0, to: 62, by: 2).reduce(0) { sum, index in
            sum + (Int(String(decoding: bytes[index..<(index + 2)], as: UTF8.self), radix: 16) ?? 0)
        }
        return body + String(format: "%02X", checksum & 255)
    }
}
