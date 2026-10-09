import Foundation

enum DeviceIdentityPreferences {
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
