import SwiftUI
import UIKit

/// 只消费原生滚动中的一段距离，余下距离和惯性仍交给 UIScrollView。
struct PausedVideoCollapseScroll: UIViewRepresentable {
    let consume: (CGFloat) -> CGFloat
    let end: () -> Void
    let canConsume: () -> Bool
    var canContinue: () -> Bool = { true }

    func makeUIView(context: Context) -> Observer { Observer() }
    func updateUIView(_ view: Observer, context: Context) {
        view.consume = consume
        view.end = end
        view.canContinue = canContinue
        if !canContinue() { view.cancelMomentum() }
        view.canConsume = canConsume
        if !canConsume() { view.releaseScroll() }
        view.attach()
    }
    static func dismantleUIView(_ view: Observer, coordinator: ()) { view.detach() }

    final class Observer: UIView {
        var consume: ((CGFloat) -> CGFloat)?
        var end: (() -> Void)?
        var canConsume: (() -> Bool)?
        var canContinue: (() -> Bool)?
        private weak var scroll: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var correcting = false
        private var consumed = false
        private var blocking = false
        private var lockedOffset = CGPoint.zero
        private var lastTranslation: CGFloat = 0
        private var displayLink: CADisplayLink?
        private var lastTimestamp: CFTimeInterval = 0
        private var momentum: CGFloat = 0
        private lazy var ticker = WeakTicker(owner: self)

        @MainActor
        private final class WeakTicker: NSObject {
            weak var owner: Observer?
            init(owner: Observer) { self.owner = owner }
            @objc func tick(_ link: CADisplayLink) { owner?.tick(link) }
        }

        override func didMoveToWindow() { super.didMoveToWindow(); attach() }
        override func didMoveToSuperview() { super.didMoveToSuperview(); attach() }

        func attach() {
            var ancestor = superview
            while let view = ancestor {
                if let target = view as? UIScrollView {
                    guard scroll !== target else { return }
                    detach()
                    scroll = target
                    target.panGestureRecognizer.addTarget(self, action: #selector(panned(_:)))
                    observation = target.observe(\.contentOffset, options: [.old, .new]) { [weak self] scroll, change in
                        MainActor.assumeIsolated {
                            self?.moved(scroll, old: change.oldValue ?? scroll.contentOffset)
                        }
                    }
                    return
                }
                ancestor = view.superview
            }
        }

        private func moved(_ scroll: UIScrollView, old: CGPoint) {
            // 布局扩高也会改变 contentOffset，这里只固定列表，不从它计算手指距离。
            guard !correcting, blocking else { return }
            correcting = true
            scroll.contentOffset = lockedOffset
            correcting = false
        }

        @objc private func panned(_ gesture: UIPanGestureRecognizer) {
            guard let scroll else { return }
            let translation = gesture.translation(in: scroll.window)
            switch gesture.state {
            case .began:
                stopMomentum()
                consumed = false
                lastTranslation = translation.y
                let velocity = gesture.velocity(in: scroll.window)
                blocking = canConsume?() == true && velocity.y < 0 && abs(velocity.y) > abs(velocity.x)
                lockedOffset = scroll.contentOffset
            case .changed:
                let delta = lastTranslation - translation.y
                lastTranslation = translation.y
                guard blocking else { return }
                let used = consume?(delta) ?? 0
                consumed = consumed || abs(used) > 0
                if canConsume?() != true {
                    blocking = false
                    // 达到收缩终点后，当前这次手势的剩余距离直接交给列表。
                    scroll.contentOffset.y = lockedOffset.y + max(0, delta - used)
                } else {
                    moved(scroll, old: lockedOffset)
                }
            case .ended:
                if blocking, consumed {
                    momentum = -gesture.velocity(in: scroll.window).y
                    lastTimestamp = 0
                    let link = CADisplayLink(target: ticker, selector: #selector(WeakTicker.tick(_:)))
                    displayLink = link
                    link.add(to: .main, forMode: .common)
                }
                if consumed { end?() }
                consumed = false
            case .cancelled, .failed:
                stopMomentum()
                blocking = false
                consumed = false
            default: break
            }
        }

        func releaseScroll() {
            // 收缩终点仍需承接同一段惯性，不能在视图刷新时将它截断。
            if displayLink == nil { blocking = false }
        }

        private func tick(_ link: CADisplayLink) {
            guard let scroll, window != nil, canContinue?() == true else {
                cancelMomentum()
                return
            }
            guard lastTimestamp > 0 else { lastTimestamp = link.timestamp; return }
            let dt = min(link.timestamp - lastTimestamp, 1.0 / 30)
            lastTimestamp = link.timestamp
            // UIScrollView 的 decelerationRate 是每毫秒速度保留比例。
            let rate = Double(scroll.decelerationRate.rawValue)
            let decay = pow(rate, dt * 1000)
            let distance = momentum * CGFloat((decay - 1) / (1000 * log(rate)))
            momentum *= CGFloat(decay)
            let used = consume?(distance) ?? 0
            let remainder = distance - used
            if abs(remainder) > 0.01 {
                let minimum = -scroll.adjustedContentInset.top
                let maximum = max(minimum, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                let proposed = lockedOffset.y + remainder
                lockedOffset.y = min(max(proposed, minimum), maximum)
                if proposed != lockedOffset.y { momentum = 0 }
            }
            moved(scroll, old: lockedOffset)
            if abs(momentum) < 5 {
                // 清掉原列表尚未结束的减速，避免释放锁定后突然跳动。
                correcting = true
                scroll.setContentOffset(lockedOffset, animated: false)
                correcting = false
                stopMomentum()
                blocking = false
            }
        }

        func cancelMomentum() {
            guard displayLink != nil else { return }
            stopMomentum()
            if let scroll {
                correcting = true
                scroll.setContentOffset(lockedOffset, animated: false)
                correcting = false
            }
            blocking = false
        }

        private func stopMomentum() {
            displayLink?.invalidate()
            displayLink = nil
            lastTimestamp = 0
            momentum = 0
        }

        func detach() {
            stopMomentum()
            observation?.invalidate()
            observation = nil
            scroll?.panGestureRecognizer.removeTarget(self, action: #selector(panned(_:)))
            scroll = nil
            blocking = false
            consumed = false
        }
    }
}
