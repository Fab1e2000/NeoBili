import Foundation
import Synchronization

/// Compile with the production networking sources and offline Stubs.swift.
/// Counts calls at the CredentialStorage boundary, never reads a real Keychain.
@main
struct BehaviorIdentityPerformance {
    static func main() async throws {
        let name = "behavior-performance.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let serialName = "behavior-sequence-performance.\(UUID())"
        let serialDefaults = UserDefaults(suiteName: serialName)!
        defer { serialDefaults.removePersistentDomain(forName: serialName) }
        let serialKey = "neobili.neuron.eventSerial"
        defaults.set(57, forKey: serialKey)
        let memory = CredentialStorage.memory()
        let epochKey = "neobili.telemetry.loginEpoch"
        let reads = Mutex(0)
        let credentials = CredentialStorage(read: { key in
            if key == epochKey { reads.withLock { $0 += 1 } }
            return memory.read(key)
        }, write: memory.write)
        let identity = DeviceIdentity(defaults: defaults, credentials: credentials,
            allowsNetwork: false, eventSerialDefaults: serialDefaults, purgeCookies: {})
        let cookies = BiliPassport.LoginCookies(sessdata: "fixture", biliJct: "fixture", dedeUserID: "42")
        await identity.saveLogin(cookies, accessKey: "fixture")
        func snapshot(_ identity: DeviceIdentity) async throws -> AppDeviceSnapshot {
            try await identity.appDeviceSnapshot(expectedSessionID: identity.loginSessionID)
        }
        let original = try await snapshot(identity)
        reads.withLock { $0 = 0 }
        let start = ContinuousClock.now
        var previousSerial = 57
        for _ in 0..<1000 {
            let current = try await identity.nextBehaviorSnapshot(expectedSessionID: identity.loginSessionID)
            precondition(current.accountEpoch == original.accountEpoch)
            precondition(current.eventSerial == previousSerial + 1)
            previousSerial = current.eventSerial ?? 0
        }
        precondition(defaults.integer(forKey: serialKey) == 57, "events must not write the standard preferences domain")
        precondition(serialDefaults.integer(forKey: serialKey) == 1057)
        let count = reads.withLock { $0 }
        print("1000 event snapshots: epoch storage reads=\(count), elapsed=\(start.duration(to: .now))")
        // Override only to reproduce the pre-optimization baseline from saved source.
        let expected = Int(ProcessInfo.processInfo.environment["EXPECTED_EPOCH_READS"] ?? "0")!
        precondition(count == expected)
        await identity.setLoginCookies(sessdata: "fixture2", biliJct: "fixture2", dedeUserID: "42")
        let relogin = try await snapshot(identity)
        precondition(relogin.accountEpoch != original.accountEpoch)
        let login = SMSPassport.Credentials(cookies: cookies, accessKey: "fixture3", refreshToken: "fixture-refresh")
        try await identity.saveSMSLogin(login, expectedSessionID: identity.loginSessionID, authorizationOnly: true)
        let authorized = try await snapshot(identity)
        precondition(authorized.accountEpoch == relogin.accountEpoch)
        try await identity.saveSMSLogin(login, expectedSessionID: identity.loginSessionID, authorizationOnly: false)
        let sms = try await snapshot(identity)
        precondition(sms.accountEpoch != authorized.accountEpoch)
        let restarted = DeviceIdentity(defaults: defaults, credentials: credentials,
            allowsNetwork: false, eventSerialDefaults: serialDefaults, purgeCookies: {})
        let resumed = try await restarted.nextBehaviorSnapshot(expectedSessionID: restarted.loginSessionID)
        precondition(resumed.eventSerial == 1058, "restart must continue the migrated sequence without gaps")
        let restored = try await snapshot(restarted)
        precondition(restored.accountEpoch == sms.accountEpoch)
        precondition(restored.accountEpoch == memory.read(epochKey))
        await identity.clearLoginCookies()
        let cleared = try await snapshot(identity)
        precondition(cleared.accountEpoch != sms.accountEpoch)
        precondition(cleared.accountEpoch == memory.read(epochKey))
        print("PASS: epoch follows cookie login, authorization, SMS login, restart and logout; event serial remains monotonic")
    }
}
