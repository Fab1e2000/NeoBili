import SwiftUI
import UIKit

/// SwiftUI onAppear runs before the incoming zoom. UIKit's completed appearance
/// lets us retain the entry card for that animation, then select the mini window
/// for all subsequent system-driven dismissals, including interactive ones.
struct VideoPagePresentationObserver: UIViewControllerRepresentable {
    let onDidAppear: () -> Void

    func makeUIViewController(context: Context) -> ObserverController {
        let controller = ObserverController()
        controller.onDidAppear = onDidAppear
        return controller
    }

    func updateUIViewController(_ controller: ObserverController, context: Context) {
        controller.onDidAppear = onDidAppear
    }

    final class ObserverController: UIViewController {
        var onDidAppear: (() -> Void)?

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
