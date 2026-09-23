import Foundation

enum PlaybackWindowSettings {
    static let storageKey = "neobili.miniPlayerEnabled"
    static let defaultValue = true

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: storageKey) as? Bool ?? defaultValue
    }
}
