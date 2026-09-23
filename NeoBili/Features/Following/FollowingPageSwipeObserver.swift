import SwiftUI
import UIKit

/// 将横向展开手势直接挂到页面 UIScrollView，避免被卡片和 SwiftUI 滚动手势抢走。
struct FollowingPageSwipeObserver: UIViewRepresentable {
    let enabled: Bool
    var side: FollowingSidebarSide = .left
    let onMove: (CGFloat) -> Void
    let onEnd: (CGFloat?) -> Void

    func makeUIView(context: Context) -> ObserverView { ObserverView() }
    func updateUIView(_ view: ObserverView, context: Context) {
        view.enabled = enabled
        view.direction = side == .left ? 1 : -1
        view.onMove = onMove
        view.onEnd = onEnd
        view.attach()
    }
    static func dismantleUIView(_ view: ObserverView, coordinator: ()) { view.detach() }

    @MainActor
    final class ObserverView: UIView, UIGestureRecognizerDelegate {
        var enabled = true
        var direction: CGFloat = 1
        var onMove: ((CGFloat) -> Void)?
        var onEnd: ((CGFloat?) -> Void)?
        private weak var scroll: UIScrollView?
        private lazy var pan: UIPanGestureRecognizer = {
            let gesture = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
            gesture.delegate = self
            gesture.maximumNumberOfTouches = 1
            gesture.cancelsTouchesInView = true
            return gesture
        }()

        override func didMoveToWindow() { super.didMoveToWindow(); attach() }
        override func didMoveToSuperview() { super.didMoveToSuperview(); attach() }
        override func layoutSubviews() { super.layoutSubviews(); attach() }

        func attach() {
            var ancestor = superview
            while let view = ancestor {
                if let target = view as? UIScrollView {
                    guard scroll !== target else { return }
                    detach()
                    scroll = target
                    target.addGestureRecognizer(pan)
                    return
                }
                ancestor = view.superview
            }
        }

        func detach() {
            scroll?.removeGestureRecognizer(pan)
            scroll = nil
        }

        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            let velocity = pan.velocity(in: window)
            return enabled && velocity.x * direction > 0 && abs(velocity.x) > abs(velocity.y) * 1.3
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            other === scroll?.panGestureRecognizer
        }

        @objc private func panned(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began, .changed:
                onMove?(gesture.translation(in: window).x * direction)
            case .ended:
                onMove?(gesture.translation(in: window).x * direction)
                onEnd?(gesture.velocity(in: window).x * direction)
            case .cancelled, .failed:
                onEnd?(nil)
            default:
                break
            }
        }
    }
}
