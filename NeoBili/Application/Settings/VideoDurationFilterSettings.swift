#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import Foundation
import Observation

@MainActor @Observable
final class VideoDurationFilterSettings {
    @ObservationIgnored private let defaults: UserDefaults
    private static let storageKey = "neobili.minimumVideoMinutes"

    var minimumMinutes: Int {
        didSet { defaults.set(minimumMinutes, forKey: Self.storageKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        minimumMinutes = min(max(defaults.integer(forKey: Self.storageKey), 0), 1440)
    }

    var minimumSeconds: Int { minimumMinutes * 60 }

    nonisolated static func seconds(from text: String) -> Int? { VideoDuration.seconds(from: text) }
}
