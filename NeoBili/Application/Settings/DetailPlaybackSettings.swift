import Foundation

enum DetailPlaybackSettings {
    static let storageKey = "neobili.detailAutoPlay"
    static let defaultValue = true

    static func isAutoPlayEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: storageKey) as? Bool ?? defaultValue
    }
}
