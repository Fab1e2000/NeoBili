import Foundation

@MainActor
private final class SurfaceProbe: PlayerSurfaceOwnershipObserver {
    private(set) var notifications = 0
    var onChange: (() -> Void)?

    func playerSurfaceOwnershipDidChange() {
        notifications += 1
        onChange?()
    }
}

@main
enum PlayerSurfaceOwnershipRegression {
    @MainActor
    static func main() {
        let original = PlayerSurfaceOwnership()
        let replacement = PlayerSurfaceOwnership()
        let mini = SurfaceProbe()
        original.addObserver(mini)
        precondition(mini.notifications == 1, "Registering an already mounted host refreshes its ownership")
        original.addObserver(mini)
        precondition(mini.notifications == 1, "Repeated SwiftUI updates must not duplicate subscriptions")
        original.presentation = .mini
        precondition(mini.notifications == 2, "The change must reach the mini synchronously without a layout callback")
        original.presentation = .mini
        precondition(mini.notifications == 2, "An unchanged destination must not generate redundant handoffs")

        // The existing mini view is rebound when a related video replaces the
        // original. Nothing in this sequence asks that view to relayout.
        original.removeObserver(mini)
        replacement.addObserver(mini)
        let afterRebind = mini.notifications
        original.presentation = .page
        original.presentation = .mini
        precondition(mini.notifications == afterRebind, "The replaced session must no longer wake the mini")
        replacement.presentation = .mini
        precondition(mini.notifications == afterRebind + 1, "The replacement's dismissal must actively notify the reused mini")

        let lateHost = SurfaceProbe()
        replacement.addObserver(lateHost)
        precondition(lateHost.notifications == 1, "A host created after dismissal still receives current ownership")
        replacement.removeObserver(lateHost)
        replacement.presentation = .page
        precondition(lateHost.notifications == 1, "A dismantled host must be disconnected")

        weak var released: SurfaceProbe?
        do {
            let temporary = SurfaceProbe()
            released = temporary
            replacement.addObserver(temporary)
        }
        precondition(released == nil, "A playing session must not retain an obsolete UI container")
        replacement.presentation = .mini

        let removesItself = SurfaceProbe()
        var didRemove = false
        removesItself.onChange = { [weak removesItself] in
            guard let removesItself else { return }
            didRemove = true
            replacement.removeObserver(removesItself)
        }
        replacement.addObserver(removesItself)
        precondition(didRemove)
        replacement.presentation = .page
        precondition(removesItself.notifications == 1, "An observer may safely unregister from its own callback")
        print("Player surface ownership regression passed: synchronous handoff, same-view session replacement, late hosts, weak lifetime, and removal")
    }
}
