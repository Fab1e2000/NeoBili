import UIKit

/// Only foreground playback suppresses the system's automatic dimming and lock.
@MainActor
final class PlaybackIdleTimer {
    private var isPlaying = false
    private var isApplicationActive: Bool
    private var appliedState: Bool?
    private let setDisabled: (Bool) -> Void

    init(
        isApplicationActive: Bool = UIApplication.shared.applicationState == .active,
        setDisabled: @escaping (Bool) -> Void = { disabled in
            if UIApplication.shared.isIdleTimerDisabled != disabled {
                UIApplication.shared.isIdleTimerDisabled = disabled
            }
        }
    ) {
        self.isApplicationActive = isApplicationActive
        self.setDisabled = setDisabled
    }

    func update(isPlaying: Bool) {
        self.isPlaying = isPlaying
        apply()
    }

    func setApplicationActive(_ active: Bool) {
        isApplicationActive = active
        apply()
    }

    private func apply() {
        let disabled = isPlaying && isApplicationActive
        guard appliedState != disabled else { return }
        appliedState = disabled
        setDisabled(disabled)
    }
}
