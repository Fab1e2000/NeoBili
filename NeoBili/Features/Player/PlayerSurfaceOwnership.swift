import Foundation

enum PlayerSurfacePresentation: Equatable { case page, mini }

@MainActor
protocol PlayerSurfaceOwnershipObserver: AnyObject {
    func playerSurfaceOwnershipDidChange()
}

/// UIKit surfaces may remain mounted at the same size while a video is replaced
/// or its page is dismissed. Ownership changes must actively wake those hosts;
/// another SwiftUI update or layout pass is not guaranteed to happen.
@MainActor
final class PlayerSurfaceOwnership {
    private struct WeakObserver {
        weak var value: (any PlayerSurfaceOwnershipObserver)?
    }

    var presentation: PlayerSurfacePresentation = .page {
        didSet {
            guard presentation != oldValue else { return }
            observers.removeAll { $0.value == nil }
            for observer in observers.compactMap(\.value) {
                observer.playerSurfaceOwnershipDidChange()
            }
        }
    }

    private var observers: [WeakObserver] = []

    func addObserver(_ observer: any PlayerSurfaceOwnershipObserver) {
        observers.removeAll { $0.value == nil }
        guard !observers.contains(where: { $0.value === observer }) else { return }
        observers.append(WeakObserver(value: observer))
        observer.playerSurfaceOwnershipDidChange()
    }

    func removeObserver(_ observer: any PlayerSurfaceOwnershipObserver) {
        observers.removeAll { $0.value == nil || $0.value === observer }
    }
}
