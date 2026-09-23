import SwiftUI

extension View {
    /// Source.player stays on the bottom accessory when mini playback is enabled.
    /// With mini playback disabled, the selected card supplies both transitions.
    /// No UIKit presentation controller or transparent hit-testing view is added.
    @ViewBuilder
    func videoTransitionSource(_ id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            modifier(MediaTransitionSourceModifier(id: id, namespace: namespace))
        } else {
            self
        }
    }
}

private struct MediaTransitionSourceModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID
    @Environment(NowPlayingStore.self) private var store: NowPlayingStore?

    func body(content: Content) -> some View {
        let source = store?.matchedTransitionSource(for: id) ?? .content(id)
        // This helper also serves dynamic-detail transitions, whose callers use
        // String IDs. Preserve those identifiers instead of boxing them in Source.
        return content.matchedTransitionSource(id: source.nativeID, in: namespace)
    }
}
