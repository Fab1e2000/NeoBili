import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Official 8.89 local branch: prefix plus three characters plus 32 UUID digits.
/// Existing persisted identities are never regenerated during an upgrade.
enum AppBuvid {
    enum Mode: String, CaseIterable, Identifiable {
        case system, random
        var id: String { rawValue }
        var title: String {
            switch self {
            case .system: String(localized: "系统派生编号")
            case .random: String(localized: "随机编号")
            }
        }
    }
    static let modeKey = "neobili.appBuvid.mode"
    // Freeze the selection for the process so in-flight requests keep one identity.
    static let launchMode = selectedMode(defaults: .standard)

    static func selectedMode(defaults: UserDefaults) -> Mode {
        if let value = defaults.string(forKey: modeKey) { return Mode(rawValue: value) ?? .system }
        return randomExperimentEnabled ? .random : .system
    }

    // Legacy experiment artifacts use random only when no explicit preference exists.
    static var randomExperimentEnabled: Bool {
        #if NEOBILI_RANDOM_BUVID_EXPERIMENT
        true
        #else
        false
        #endif
    }

    static func randomExperimentIdentifier(defaults: UserDefaults, credentials: CredentialStorage) -> String {
        let key = "neobili.experiment.randomBuvid.v1"
        if let value = defaults.string(forKey: key), !value.isEmpty { return value }
        if let value = credentials.read(key), !value.isEmpty {
            defaults.set(value, forKey: key)
            return value
        }
        // Random installation seed, intentionally not the phone's actual IDFV.
        let value = generate(idfv: UUID().uuidString)!
        defaults.set(value, forKey: key)
        credentials.write(value, key)
        return value
    }

    static func experimentRegistrationStorage(_ base: CredentialStorage) -> CredentialStorage {
        let prefix = "neobili.experiment.randomBuvid.v1."
        return CredentialStorage(read: { base.read(prefix + $0) },
                                 write: { value, key in base.write(value, prefix + key) })
    }

    static func generate(idfa: String? = nil, idfv: String?) -> String? {
        func normalized(_ value: String?) -> String? {
            guard let value else { return nil }
            let digits = value.replacingOccurrences(of: "-", with: "").uppercased()
            guard digits.count == 32, digits.allSatisfy(\.isHexDigit),
                  digits != String(repeating: "0", count: 32) else { return nil }
            return digits
        }
        let advertising = normalized(idfa)
        guard let digits = advertising ?? normalized(idfv) else { return nil }
        let chars = Array(digits)
        return "\(advertising == nil ? "Y" : "Z")\(chars[2])\(chars[12])\(chars[22])\(digits)"
    }

    static func vendorIdentifier() async -> String? {
        #if canImport(UIKit)
        return await MainActor.run { UIDevice.current.identifierForVendor?.uuidString }
        #else
        return nil
        #endif
    }
}
