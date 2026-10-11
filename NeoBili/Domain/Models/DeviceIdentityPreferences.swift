import Foundation

enum DeviceIdentityPreferences {
    static let customKey = "neobili.appBuvid.custom"
    static let launchCustomBuvid = customBuvid(defaults: .standard)
    static func normalizedCustomBuvid(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (16...128).contains(value.count), value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return nil }
        return value
    }
    static func customBuvid(defaults: UserDefaults) -> String? {
        defaults.string(forKey: customKey).flatMap(normalizedCustomBuvid)
    }
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

}
