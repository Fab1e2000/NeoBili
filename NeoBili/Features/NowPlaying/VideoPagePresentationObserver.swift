import SwiftUI
import UIKit

/// SwiftUI onAppear runs before the incoming zoom. UIKit's completed appearance
/// lets us retain the entry card for that animation, then select the mini window
/// for all subsequent system-driven dismissals, including interactive ones.
struct VideoPagePresentationObserver: UIViewControllerRepresentable {
    let onDidAppear: () -> Void
    var onInteractionBegan: () -> Void = {}
    var onInteractionEnded: (Bool) -> Void = { _ in }

    func makeUIViewController(context: Context) -> ObserverController {
        let controller = ObserverController()
        controller.onDidAppear = onDidAppear
        controller.onInteractionBegan = onInteractionBegan
        controller.onInteractionEnded = onInteractionEnded
        return controller
    }

    func updateUIViewController(_ controller: ObserverController, context: Context) {
        controller.onDidAppear = onDidAppear
        controller.onInteractionBegan = onInteractionBegan
        controller.onInteractionEnded = onInteractionEnded
    }

    final class ObserverController: UIViewController {
        var onDidAppear: (() -> Void)?
        var onInteractionBegan: (() -> Void)?
        var onInteractionEnded: ((Bool) -> Void)?

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            guard let coordinator = transitionCoordinator, coordinator.isInteractive else { return }
            var owner: UIViewController? = self
            while let current = owner, !current.isBeingDismissed { owner = current.parent }
            guard owner != nil else { return }
            onInteractionBegan?()
            coordinator.animate(alongsideTransition: nil) { [weak self] context in
                self?.onInteractionEnded?(context.isCancelled)
            }
        }

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
            view.backgroundColor = .clear
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onDidAppear?()
        }
    }
}
