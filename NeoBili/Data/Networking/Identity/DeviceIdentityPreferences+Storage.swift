import NeoBiliDomain
import Foundation

extension DeviceIdentityPreferences {
    // Freeze the selection for the process so in-flight requests keep one identity.
    public static let launchCustomBuvid = customBuvid(defaults: .standard)
    static func customBuvid(defaults: UserDefaults) -> String? {
        defaults.string(forKey: customKey).flatMap(normalizedCustomBuvid)
    }
}
