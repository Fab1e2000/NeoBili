import Foundation
import CommonCrypto
import Security
#if canImport(UIKit)
import UIKit
#endif

/// Guest registration is independent of fingerprint registration and account login.
/// DEV-03/09: 8.89 static crypto/lifecycle; 9.13 captured endpoint/body shape.
enum AppGuestProtocol {
    static func material(buvid: String, vendorID: String?, firstRunMilliseconds: Int64,
                         advertisingID: String? = nil) throws -> Data {
        var fields = ["DeviceType": "ios", "Buvid": buvid, "fts": String(firstRunMilliseconds)]
        fields["IDFV"] = vendorID
        fields["IDFA"] = advertisingID // nil is omitted, never invented or requested through ATT.
        return try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
    }

    static func encrypt(material: Data, publicKey: String, key suppliedKey: Data? = nil) throws -> [String: String] {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".utf8)
        let key: Data
        if let suppliedKey { key = suppliedKey } else {
            var words = [UInt32](repeating: 0, count: 16)
            guard SecRandomCopyBytes(kSecRandomDefault, words.count * MemoryLayout<UInt32>.size, &words) == errSecSuccess else {
                throw AppProto.Failure.malformed
            }
            key = Data(words.map { alphabet[Int($0 % 62)] })
        }
        guard key.count == 16, key.allSatisfy({ alphabet.contains($0) }), !material.isEmpty else {
            throw AppProto.Failure.malformed
        }
        var output = Data(count: material.count + kCCBlockSizeAES128), count = 0
        let status = output.withUnsafeMutableBytes { destination in
            key.withUnsafeBytes { secret in material.withUnsafeBytes { source in
                CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                        secret.baseAddress, key.count, secret.baseAddress, source.baseAddress, material.count,
                        destination.baseAddress, destination.count, &count)
            } }
        }
        guard status == kCCSuccess else { throw AppProto.Failure.malformed }
        output.removeSubrange(count..<output.count)
        return ["device_info": output.map { String(format: "%02x", $0) }.joined(),
                "dt": try PasswordCipher.encryptRSA(key, publicKeyPEM: publicKey).base64EncodedString()]
    }

    static func request(path: String, fields: [String: String] = [:], headers: [String: String],
                        timestamp: Int, isPost: Bool) -> URLRequest {
        var parameters = AppClientIdentity.parameters.merging([
            "actionKey": "appkey", "statistics": AppClientIdentity.statistics, "c_locale": "zh-Hans_CN",
            "s_locale": "zh-Hans_CN", "disable_rcmd": "0", "teenagers_age": "0", "sdk_ver": "0.1.15"
        ]) { _, value in value }
        parameters.merge(fields) { _, value in value }
        let encoded = AppSigner.queryString(from: AppSigner.signed(parameters, purpose: .passport, timestamp: timestamp))
        var components = URLComponents(string: "https://passport.bilibili.com/\(path)")!
        if !isPost { components.percentEncodedQuery = encoded }
        var request = URLRequest(url: components.url!)
        request.httpMethod = isPost ? "POST" : "GET"
        request.timeoutInterval = 10
        request.httpShouldHandleCookies = false
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.setValue(AppClientIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        if isPost {
            request.httpBody = Data(encoded.utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
}

actor AppGuestRegistration {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    typealias VendorIdentifier = @Sendable () async -> String?
    private let credentials: CredentialStorage
    private let transport: Transport
    private let vendorIdentifier: VendorIdentifier
    private let clock: @Sendable () -> TimeInterval
    private var id: Int64?
    private var pending: Task<Int64?, Never>?
    private var pendingBuvid: String?
    private var generation = UUID()
    private let firstRunMilliseconds: Int64
    static let storageKey = "neobili.ios.guest.id"
    static let firstRunKey = "neobili.ios.guest.firstRunMilliseconds"

    init(credentials: CredentialStorage,
         transport: @escaping Transport = { try await AppNetwork.session.data(for: $0) },
         vendorIdentifier: @escaping VendorIdentifier = {
             #if canImport(UIKit)
             return await MainActor.run { UIDevice.current.identifierForVendor?.uuidString }
             #else
             return nil
             #endif
         }, clock: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.credentials = credentials; self.transport = transport; self.vendorIdentifier = vendorIdentifier; self.clock = clock
        if let raw = credentials.read(Self.storageKey), let parsed = Int64(raw), Self.isValid(parsed) { id = parsed }
        if let raw = credentials.read(Self.firstRunKey), let parsed = Int64(raw), parsed != 0 {
            firstRunMilliseconds = parsed
        } else {
            firstRunMilliseconds = Int64(clock() * 1000)
            credentials.write(String(firstRunMilliseconds), Self.firstRunKey)
        }
    }

    static func isValid(_ value: Int64) -> Bool { value != 0 && value != -2 }
    func cachedID() -> Int64? { id }

    /// Call once at setup and on application-active. A failure is not cached;
    /// a later activation retries. Coalescing is local safety, not a claimed official rule.
    func load(buvid: String, headers: [String: String]) async -> Int64? {
        if let id { return id }
        if let pending, pendingBuvid == buvid { return await pending.value }
        pending?.cancel()
        let requestGeneration = UUID()
        generation = requestGeneration
        let transport = transport, vendorIdentifier = vendorIdentifier, clock = clock, firstRun = firstRunMilliseconds
        let task = Task<Int64?, Never> {
            do {
                let keyRequest = AppGuestProtocol.request(path: "x/passport-login/web/key", headers: headers,
                                                         timestamp: Int(clock()), isPost: false)
                let keyData = try await Self.response(keyRequest, transport: transport)
                try Task.checkCancellation()
                guard let key = keyData["key"] as? String, !key.isEmpty else { return nil }
                let material = try AppGuestProtocol.material(buvid: buvid, vendorID: await vendorIdentifier(), firstRunMilliseconds: firstRun)
                let fields = try AppGuestProtocol.encrypt(material: material, publicKey: key)
                let register = AppGuestProtocol.request(path: "x/passport-user/guest/reg", fields: fields,
                                                       headers: headers, timestamp: Int(clock()), isPost: true)
                let reply = try await Self.response(register, transport: transport)
                try Task.checkCancellation()
                let parsed: Int64?
                if let value = reply["guest_id"] as? String { parsed = Int64(value) }
                else if let value = reply["guest_id"] as? NSNumber {
                    parsed = CFGetTypeID(value) == CFBooleanGetTypeID() ? nil : Int64(value.stringValue)
                } else { parsed = nil }
                guard let parsed, Self.isValid(parsed) else { return nil }
                return parsed
            } catch { return nil }
        }
        pending = task
        pendingBuvid = buvid
        let result = await task.value
        guard generation == requestGeneration else { return nil }
        pending = nil
        pendingBuvid = nil
        if let result { id = result; credentials.write(String(result), Self.storageKey) }
        return result
    }

    private static func response(_ request: URLRequest, transport: Transport) async throws -> [String: Any] {
        let (bytes, response) = try await transport(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("application/json") == true,
              let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let code = object["code"] as? NSNumber, CFGetTypeID(code) != CFBooleanGetTypeID(), code.intValue == 0,
              let data = object["data"] as? [String: Any] else { throw AppProto.Failure.malformed }
        return data
    }
}
