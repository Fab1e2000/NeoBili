import NeoBiliDomain
import Foundation
import Observation

/// 播放器播放模式（洗脑循环、自动切集/自动连播）的全局共享偏好。
@MainActor @Observable
final class PlaybackModePreferences {
    private(set) var loopEnabled: Bool
    private(set) var autoAdvanceEnabled: Bool
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loopEnabled = PlaybackModeSettings.isLoopEnabled(in: defaults)
        autoAdvanceEnabled = PlaybackModeSettings.isAutoAdvanceEnabled(in: defaults)
    }

    func setLoopEnabled(_ enabled: Bool) {
        guard loopEnabled != enabled else { return }
        loopEnabled = enabled
        defaults.set(enabled, forKey: PlaybackModeSettings.loopEnabledKey)
    }

    func setAutoAdvanceEnabled(_ enabled: Bool) {
        guard autoAdvanceEnabled != enabled else { return }
        autoAdvanceEnabled = enabled
        defaults.set(enabled, forKey: PlaybackModeSettings.autoAdvanceEnabledKey)
    }

    func toggleLoop() {
        setLoopEnabled(!loopEnabled)
    }

    func toggleAutoAdvance() {
        setAutoAdvanceEnabled(!autoAdvanceEnabled)
    }
}
