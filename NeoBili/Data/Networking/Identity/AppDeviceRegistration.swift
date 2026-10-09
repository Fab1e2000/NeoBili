import Foundation
import CommonCrypto
import Security
#if canImport(UIKit)
import UIKit
#endif

/// Version-bounded iOS registration adapter. Missing/unavailable device facts
/// remain absent, not fabricated. Current-server acceptance is a separate check.
enum IOSFingerprintProtocol {
    static let publicKey = """
    -----BEGIN PUBLIC KEY-----
    MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDOCQs2X+3WRvTcieZ7bncZuNDE
    O0JvE/QCJQPUf6Csa8uc7fD+13TLBFe6qf31MljfX2SxZLvyLN2pWlH+TCeuApH6
    EjKint1meowkdcvulu1Y34FzBFbT8/o4mVS9QYvQACi29pXil56XTlXy2KxhqWWq
    Ahxx37YGj/aRiMpbZwIDAQAB
    -----END PUBLIC KEY-----
    """

    static func encryptedBody(material: Data, key suppliedKey: Data? = nil, publicKeyPEM: String = publicKey) throws -> Data {
        guard !material.isEmpty, material.count <= 64 * 1024 else { throw AppProto.Failure.oversized }
        let key: Data
        if let suppliedKey { key = suppliedKey } else {
            var bytes = [UInt8](repeating: 0, count: 16)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AppProto.Failure.malformed }
            key = Data(bytes.map { $0 % 127 + 1 })
        }
        guard key.count == 16, key.allSatisfy({ (1...127).contains($0) }) else { throw AppProto.Failure.malformed }
        var encrypted = Data(count: material.count + kCCBlockSizeAES128), length = 0
        let status = encrypted.withUnsafeMutableBytes { output in
            material.withUnsafeBytes { input in
                key.withUnsafeBytes { secret in
                    CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding), secret.baseAddress, key.count,
                        nil, input.baseAddress, material.count, output.baseAddress, output.count, &length)
                }
            }
        }
        guard status == kCCSuccess else { throw AppProto.Failure.malformed }
        encrypted.removeSubrange(length..<encrypted.count)
        func hex(_ bytes: Data) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
        let wrapped = try PasswordCipher.encryptRSA(Data(hex(key).utf8), publicKeyPEM: publicKeyPEM)
        return try JSONSerialization.data(withJSONObject: ["key": hex(wrapped), "content": hex(encrypted)], options: [.sortedKeys])
    }

    static func material(buvid: String, mid: Int?) async -> Data? {
        #if canImport(UIKit)
        return await MainActor.run {
            let device = UIDevice.current
            guard let vendor = device.identifierForVendor?.uuidString else { return nil }
            // Explicit subset of proven descriptor fields with actual local values.
            // Motion, carrier, camera, storage, time-seed and SDK-derived facts are
            // omitted until their exact providers are implemented and verified.
            var data = AppProto.string(1, "ios") + AppProto.integer(2, device.userInterfaceIdiom.rawValue)
            data += AppProto.string(3, device.systemVersion) + AppProto.string(6, vendor)
            data += AppProto.string(7, AppClientIdentity.deviceName) + AppProto.string(8, "Apple")
            data += AppProto.string(18, device.systemName) + AppProto.integer(19, Int(ProcessInfo.processInfo.physicalMemory))
            data += AppProto.string(20, device.name) + AppProto.integer(23, 1)
            data += AppProto.string(24, AppClientIdentity.version) + AppProto.string(25, AppClientIdentity.build)
            if let mid { data += AppProto.string(26, String(mid)) }
            // buvidLocal is not the tracking BUVID passed in headers. Its
            // distinct producer remains unresolved; never substitute one for it.
            data += AppProto.integer(50, ProcessInfo.processInfo.processorCount)
            #if targetEnvironment(simulator)
            data += AppProto.integer(54, 1)
            #else
            data += AppProto.integer(54, 0)
            #endif
            return data
        }
        #else
        return nil
        #endif
    }
}

actor AppDeviceRegistration {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    typealias Material = @Sendable (String, Int?) async -> Data?
    private struct Cache: Codable { let buvid: String; let id: String; let expiry: TimeInterval }
    private let credentials: CredentialStorage
    private let transport: Transport
    private let material: Material
    private let clock: @Sendable () -> TimeInterval
    private var cache: Cache?
    private var pending: Task<String?, Never>?
    private var pendingBuvid: String?
    private var retryAfter: TimeInterval = 0
    private static let storageKey = "neobili.ios.fingerprint.registration"

    init(credentials: CredentialStorage, transport: @escaping Transport = { try await AppNetwork.session.data(for: $0) },
         material: @escaping Material = { await IOSFingerprintProtocol.material(buvid: $0, mid: $1) },
         clock: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.credentials = credentials; self.transport = transport; self.material = material; self.clock = clock
        if let value = credentials.read(Self.storageKey), let data = value.data(using: .utf8) {
            cache = try? JSONDecoder().decode(Cache.self, from: data)
        }
    }

    func cachedID(buvid: String) -> String? { cache?.buvid == buvid ? cache?.id : nil }

    func register(buvid: String, mid: Int?, accessKey: String? = nil, headers: [String: String]) async -> String? {
        if let cache, cache.buvid == buvid, cache.expiry > clock() { return cache.id }
        if let pending {
            guard pendingBuvid == buvid else { return cachedID(buvid: buvid) }
            return await pending.value
        }
        guard clock() >= retryAfter else { return cachedID(buvid: buvid) }
        retryAfter = clock() + 120
        let transport = transport, material = material
        let task = Task<String?, Never> {
            guard let bytes = await material(buvid, mid), let body = try? IOSFingerprintProtocol.encryptedBody(material: bytes) else { return nil }
            var parameters = AppClientIdentity.parameters
            parameters.merge(["actionKey": "appkey", "statistics": AppClientIdentity.statistics,
                "c_locale": "zh-Hans_CN", "s_locale": "zh-Hans_CN", "channel": "pink_overseas",
                "disable_rcmd": "0", "access_key": accessKey ?? ""]) { _, value in value }
            var url = URLComponents(string: "https://app.bilibili.com/x/resource/fingerprint")!
            url.percentEncodedQuery = AppSigner.queryString(from: AppSigner.signed(parameters))
            guard let destination = url.url else { return nil }
            var request = URLRequest(url: destination)
            request.httpMethod = "POST"; request.httpBody = body; request.timeoutInterval = 10
            request.httpShouldHandleCookies = false
            for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
            request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
            guard let (data, response) = try? await transport(request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let reply = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  (reply["code"] as? Int).map({ $0 == 0 }) ?? true,
                  let value = (reply["data"] as? [String: Any])?["bili_deviceId"] as? String,
                  !value.isEmpty, value.utf8.count <= 1024 else { return nil }
            return value
        }
        pending = task
        pendingBuvid = buvid
        let result = await task.value
        pending = nil
        pendingBuvid = nil
        if let result {
            let value = Cache(buvid: buvid, id: result, expiry: clock() + 86400)
            cache = value
            if let data = try? JSONEncoder().encode(value), let text = String(data: data, encoding: .utf8) {
                credentials.write(text, Self.storageKey)
            }
        }
        return result ?? cachedID(buvid: buvid)
    }
}
