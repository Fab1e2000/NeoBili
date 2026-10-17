import Foundation

extension DeviceIdentityPreferences {
    // Freeze the selection for the process so in-flight requests keep one identity.
    static let launchCustomBuvid = customBuvid(defaults: .standard)
    static let launchMode = selectedMode(defaults: .standard)
    static func customBuvid(defaults: UserDefaults) -> String? {
        defaults.string(forKey: customKey).flatMap(normalizedCustomBuvid)
    }
    static func selectedMode(defaults: UserDefaults) -> Mode {
        if let value = defaults.string(forKey: modeKey) { return Mode(rawValue: value) ?? .system }
        return randomExperimentEnabled ? .random : .system
    }
}
