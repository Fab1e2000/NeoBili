import SwiftUI

/// Shared dynamic-property storage keeps card modifiers responsive to settings
/// without adding an observable singleton or rebuilding the app's whole root.
struct CardAnimationPreferences: DynamicProperty {
    @Environment(\.videoCardAnimationOverrides) private var sourceOverrides
    @AppStorage(CardAnimationSettings.masterKey) private var master = CardAnimationSettings.defaultValue
    @AppStorage(CardAnimationSettings.videoEnterKey) private var videoEnter = CardAnimationSettings.defaultValue
    @AppStorage(CardAnimationSettings.videoExitKey) private var videoExit = CardAnimationSettings.defaultValue
    @AppStorage(CardAnimationSettings.dynamicEnterKey) private var dynamicEnter = CardAnimationSettings.defaultValue
    @AppStorage(CardAnimationSettings.dynamicExitKey) private var dynamicExit = CardAnimationSettings.defaultValue
    @AppStorage(CardAnimationSettings.pageEnterKey) private var pageEnter = CardAnimationSettings.defaultValue

    func isEnabled(category: CardAnimationCategory, phase: CardAnimationPhase) -> Bool {
        guard master else { return false }
        switch (category, phase) {
        case (.video, .enter): return sourceOverrides.enter ?? videoEnter
        case (.video, .exit): return sourceOverrides.exit ?? videoExit
        case (.dynamic, .enter): return dynamicEnter
        case (.dynamic, .exit): return dynamicExit
        case (.page, _): return pageEnter
        }
    }
}

struct VideoCardAnimationOverrides: Equatable {
    var enter: Bool?
    var exit: Bool?
}

extension EnvironmentValues {
    @Entry var videoCardAnimationSource: VideoCardAnimationSource? = nil
    @Entry var videoCardAnimationOverrides = VideoCardAnimationOverrides()
}

/// Each page observes only its two optional overrides. Missing values keep
/// following the pre-existing video preferences, without a migration write.
struct VideoCardAnimationPreferences: DynamicProperty {
    @AppStorage(CardAnimationSettings.masterKey) private var master = CardAnimationSettings.defaultValue
    @AppStorage(CardAnimationSettings.videoEnterKey) private var legacyEnter = CardAnimationSettings.defaultValue
    @AppStorage(CardAnimationSettings.videoExitKey) private var legacyExit = CardAnimationSettings.defaultValue
    @AppStorage private var enter: Bool?
    @AppStorage private var exit: Bool?

    init(source: VideoCardAnimationSource) {
        _enter = AppStorage(CardAnimationSettings.storageKey(source: source, phase: .enter))
        _exit = AppStorage(CardAnimationSettings.storageKey(source: source, phase: .exit))
    }

    var overrides: VideoCardAnimationOverrides { VideoCardAnimationOverrides(enter: enter, exit: exit) }

    func isEnabled(phase: CardAnimationPhase) -> Bool {
        master && (phase == .enter ? (enter ?? legacyEnter) : (exit ?? legacyExit))
    }
}

private struct VideoCardAnimationScope: ViewModifier {
    let source: VideoCardAnimationSource
    private var preferences: VideoCardAnimationPreferences

    init(source: VideoCardAnimationSource) {
        self.source = source
        preferences = VideoCardAnimationPreferences(source: source)
    }

    func body(content: Content) -> some View {
        content
            .environment(\.videoCardAnimationSource, source)
            .environment(\.videoCardAnimationOverrides, preferences.overrides)
    }
}

extension View {
    func videoCardAnimationSource(_ source: VideoCardAnimationSource) -> some View {
        modifier(VideoCardAnimationScope(source: source))
    }
}
