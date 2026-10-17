import Foundation

/// Synchronous persistence keeps write/read-back verification inside the identity actor's transaction.
struct AccountCredentialPersistence: Sendable {
    let storage: CredentialStorage
    let scope: String
    private var credentials: CredentialStorage { storage }
    private static let sessdataKeychainKey = "neobili.sessdata"
    private static let biliJctKeychainKey = "neobili.bili_jct"
    private static let dedeUserIDKeychainKey = "neobili.dedeuserid"
    private static let accessKeyKeychainKey = "neobili.access_key"
    private static let accessKeyClientKey = "neobili.access_key.client"
    private static let telemetryEpochKey = "neobili.telemetry.loginEpoch"

    private static let renewalKey = "neobili.login.bundle.v1"
    private struct LoginBundle: Codable {
        let scope: String
        let epoch: String
        let value: SMSLoginModels.Credentials
    }

    struct Restored: Sendable {
        var telemetryEpoch: String?
        var sessdata: String?
        var csrf: String?
        var accountID: String?
        var accessKey: String?
        var needsMigration = false
        var renewableLogin: SMSLoginModels.Credentials?
    }

    func restoreTelemetryEpoch() -> String? {
        if let epoch = credentials.read(Self.telemetryEpochKey) { return epoch }
        return replaceTelemetryEpoch(UUID().uuidString)
    }

    func restoreLogin(telemetryEpoch: String?) -> Restored {
        var restored = Restored(telemetryEpoch: telemetryEpoch)
        restored.sessdata = credentials.read(Self.sessdataKeychainKey)
        restored.csrf = credentials.read(Self.biliJctKeychainKey)
        restored.accountID = credentials.read(Self.dedeUserIDKeychainKey)
        // 不同 scope 的旧凭据来自 Android/HD；保留 Cookie，由 AccountStore 换取 iOS 凭据。
        if credentials.read(Self.accessKeyClientKey) == scope {
            restored.accessKey = credentials.read(Self.accessKeyKeychainKey)
        } else {
            restored.needsMigration = credentials.read(Self.accessKeyKeychainKey)?.isEmpty == false
        }
        if let text = credentials.read(Self.renewalKey), let bytes = text.data(using: .utf8),
           let bundle = try? JSONDecoder().decode(LoginBundle.self, from: bytes),
           bundle.scope == scope {
            credentials.write(bundle.epoch, Self.telemetryEpochKey)
            restored.telemetryEpoch = credentials.read(Self.telemetryEpochKey)
            restored.renewableLogin = bundle.value
            restored.sessdata = bundle.value.cookies.sessdata
            restored.csrf = bundle.value.cookies.biliJct
            restored.accountID = bundle.value.cookies.dedeUserID
            restored.accessKey = bundle.value.accessKey
            restored.needsMigration = false
        }
        return restored
    }

    func replaceTelemetryEpoch(_ value: String) -> String? {
        credentials.write(value, Self.telemetryEpochKey)
        // Preserve the read-back result even when a Keychain write fails.
        return credentials.read(Self.telemetryEpochKey)
    }

    func writeLegacyCookies(sessdata: String, csrf: String, accountID: String) {
        credentials.write(sessdata, Self.sessdataKeychainKey)
        credentials.write(csrf, Self.biliJctKeychainKey)
        credentials.write(accountID, Self.dedeUserIDKeychainKey)
    }

    func writeAccessKey(_ accessKey: String?) {
        credentials.write(nil, Self.accessKeyClientKey)
        credentials.write(accessKey, Self.accessKeyKeychainKey)
        credentials.write(accessKey?.isEmpty == false ? scope : nil, Self.accessKeyClientKey)
    }

    func clearLegacyLogin() {
        credentials.write(nil, Self.sessdataKeychainKey)
        credentials.write(nil, Self.biliJctKeychainKey)
        credentials.write(nil, Self.dedeUserIDKeychainKey)
        credentials.write(nil, Self.accessKeyKeychainKey)
        credentials.write(nil, Self.accessKeyClientKey)
    }

    func discardRenewal() { credentials.write(nil, Self.renewalKey) }

    func saveVerifiedBundle(_ value: SMSLoginModels.Credentials, epoch: String) throws {
        let bytes = try JSONEncoder().encode(LoginBundle(scope: scope, epoch: epoch, value: value))
        guard let text = String(data: bytes, encoding: .utf8) else { throw AppLoginRenewal.Failure.storage }
        credentials.write(text, Self.renewalKey)
        guard credentials.read(Self.renewalKey) == text else { throw AppLoginRenewal.Failure.storage }
    }

    func writeLegacyMirror(_ value: SMSLoginModels.Credentials) {
        credentials.write(value.cookies.sessdata, Self.sessdataKeychainKey)
        credentials.write(value.cookies.biliJct, Self.biliJctKeychainKey)
        credentials.write(value.cookies.dedeUserID, Self.dedeUserIDKeychainKey)
        credentials.write(value.accessKey, Self.accessKeyKeychainKey)
        credentials.write(scope, Self.accessKeyClientKey)
    }
}
