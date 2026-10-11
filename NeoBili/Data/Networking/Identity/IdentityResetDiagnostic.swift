#if DEBUG
import Foundation

/// Explicitly enabled diagnostic build, executed before any identity singleton loads.
enum IdentityResetDiagnostic {
    static let marker = "neobili.diagnostic.identityReset.once.9e8fe49a"
    static let registrationKeys = ["neobili.ios.fingerprint.registration", "neobili.ios.guest.id",
                                   "neobili.ios.guest.firstRunMilliseconds", "neobili.app.ticket"]
    static let credentialKeys = ["neobili.sessdata", "neobili.bili_jct", "neobili.dedeuserid",
        "neobili.access_key", "neobili.access_key.client", "neobili.login.bundle.v1",
        "neobili.telemetry.loginEpoch", "neobili.appBuvid", "neobili.experiment.randomBuvid.v1",
        "neobili.device.localBUVID", "neobili.device.firstRunMilliseconds"] + registrationKeys
        + registrationKeys.map { "neobili.experiment.randomBuvid.v1." + $0 }
    static let preferenceKeys = ["neobili.buvid3", "neobili.buvid4", "neobili.appBuvid",
        "neobili.experiment.randomBuvid.v1", "neobili.debug.recommendationBuvid",
        "neobili.cachedAccountProfile", "neobili.wbi.mixinKey", "neobili.wbi.mixinKeySavedAt",
        "neobili.neuron.eventSerial"]
    enum Failure: Error { case credentialDeletion }

    @discardableResult
    static func resetOnce(defaults: UserDefaults, credentials: CredentialStorage,
                          sequenceDefaults: UserDefaults, clearNetworking: () throws -> Void) throws -> Bool {
        guard !defaults.bool(forKey: marker) else { return false }
        for key in credentialKeys { credentials.write(nil, key) }
        guard credentialKeys.allSatisfy({ credentials.read($0) == nil }) else { throw Failure.credentialDeletion }
        for key in preferenceKeys { defaults.removeObject(forKey: key) }
        sequenceDefaults.removeObject(forKey: "neobili.neuron.eventSerial")
        try clearNetworking()
        // A system-derived identifier would reproduce the old IDFV identity.
        // This diagnostic explicitly creates a fresh, persisted random identity.
        let buvid = AppBuvid.generate(idfv: UUID().uuidString)!
        let key = "neobili.experiment.randomBuvid.v1"
        credentials.write(buvid, key)
        guard credentials.read(key) == buvid else { throw Failure.credentialDeletion }
        defaults.set(buvid, forKey: key)
        defaults.set("random", forKey: "neobili.appBuvid.mode")
        defaults.set(true, forKey: marker)
        return true
    }

    static func clearNetworkingCaches() throws {
        for cookie in HTTPCookieStorage.shared.cookies ?? [] {
            let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            if domain == "bilibili.com" || domain.hasSuffix(".bilibili.com")
                || domain == "biliapi.net" || domain.hasSuffix(".biliapi.net") {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
        URLCache.shared.removeAllCachedResponses()
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        for name in ["RecommendationClickQueue", "BehaviorQueue", "RecommendationDiagnostics"] {
            let folder = support.appendingPathComponent(name, isDirectory: true)
            if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
        }
    }
}
#endif
