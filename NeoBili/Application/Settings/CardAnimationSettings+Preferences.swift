import Foundation

extension CardAnimationSettings {
    static func isEnabled(
        category: CardAnimationCategory,
        phase: CardAnimationPhase,
        source: VideoCardAnimationSource? = nil,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard supports(category: category, phase: phase, source: source),
              value(for: masterKey, defaults: defaults) else { return false }
        if category == .video, let source,
           let override = defaults.object(forKey: storageKey(source: source, phase: phase)) as? Bool {
            return override
        }
        // Upgrades preserve existing choices until that page is configured.
        return value(for: storageKey(category: category, phase: phase), defaults: defaults)
    }

    private static func value(for key: String, defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultValue
    }

    /// Race the animation deadline with preference changes. Disabling an effect
    /// releases its staged content immediately, without leaving a sleeping task.
    static func waitWhileEnabled(
        for seconds: TimeInterval,
        category: CardAnimationCategory,
        phase: CardAnimationPhase,
        source: VideoCardAnimationSource? = nil
    ) async throws {
        try Task.checkCancellation()
        guard seconds > 0, seconds.isFinite, isEnabled(category: category, phase: phase, source: source) else { return }
        // Register before launching tasks so a setting changed this turn cannot
        // be missed between the enabled check and awaiting the next event.
        let changes = NotificationCenter.default.notifications(named: didChangeNotification)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await Task.sleep(for: .seconds(seconds)) }
            group.addTask {
                guard isEnabled(category: category, phase: phase, source: source) else { return }
                for await _ in changes {
                    try Task.checkCancellation()
                    if !isEnabled(category: category, phase: phase, source: source) { return }
                }
            }
            defer { group.cancelAll() }
            _ = try await group.next()
        }
        try Task.checkCancellation()
    }
}
