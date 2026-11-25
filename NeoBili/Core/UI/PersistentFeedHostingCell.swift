import SwiftUI
import UIKit

/// Preserve one hosting controller across card reuse while keeping
/// the exact same SwiftUI content, animation modifiers, and interaction handlers.
final class PersistentFeedHostingCell: UICollectionViewCell {
    private var host: UIHostingController<AnyView>?

    func setContent(_ content: AnyView) {
        if let host {
            host.rootView = content
        } else {
            let host = UIHostingController(rootView: content)
            host.safeAreaRegions = []
            host.sizingOptions = []
            host.view.backgroundColor = .clear
            host.view.frame = contentView.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            contentView.addSubview(host.view)
            self.host = host
            attachHostIfVisible()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            if let host, host.parent != nil {
                host.willMove(toParent: nil)
                host.removeFromParent()
            }
        } else {
            attachHostIfVisible()
        }
    }

    private func attachHostIfVisible() {
        guard window != nil, let host, host.parent == nil else { return }
        var responder: UIResponder? = next
        while let current = responder {
            if let parent = current as? UIViewController {
                parent.addChild(host)
                host.didMove(toParent: parent)
                return
            }
            responder = current.next
        }
    }

    override func preferredLayoutAttributesFitting(_ attributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        // Video cells already have absolute geometry from HomeCardLayout.
        attributes
    }
}
