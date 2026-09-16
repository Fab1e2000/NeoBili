import SwiftUI
import UIKit

/// 只消费原生滚动中的一段距离，余下距离和惯性仍交给 UIScrollView。
struct PausedVideoCollapseScroll: UIViewRepresentable {
    let consume: (CGFloat) -> CGFloat
    let end: () -> Void
    let canConsume: (CGFloat) -> Bool
    var canContinue: () -> Bool = { true }

    func makeUIView(context: Context) -> Observer { Observer() }
    func updateUIView(_ view: Observer, context: Context) {
        view.consume = consume
        view.end = end
        view.canContinue = canContinue
        if !canContinue() { view.cancelMomentum() }
        view.canConsume = canConsume
        if !canConsume(1), !canConsume(-1) { view.releaseScroll() }
        view.attach()
    }
    static func dismantleUIView(_ view: Observer, coordinator: ()) { view.detach() }

    final class Observer: UIView {
        var consume: ((CGFloat) -> CGFloat)?
        var end: (() -> Void)?
        var canConsume: ((CGFloat) -> Bool)?
        var canContinue: (() -> Bool)?
        private weak var scroll: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var correcting = false
        private var consumed = false
        private var blocking = false
        private var lockedOffset = CGPoint.zero
        private var lastTranslation: CGFloat = 0
        private var lastOffset = CGPoint.zero
        private var verticalDrag = false
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
            handlePan(state: gesture.state, translation: gesture.translation(in: scroll?.window),
                      velocity: gesture.velocity(in: scroll?.window))
        }

        func handlePan(state: UIGestureRecognizer.State, translation: CGPoint, velocity: CGPoint) {
            guard let scroll else { return }
            switch state {
            case .began:
                stopMomentum()
                consumed = false
                blocking = false
                lastTranslation = translation.y
                lastOffset = scroll.contentOffset
                verticalDrag = abs(velocity.y) > abs(velocity.x)
            case .changed:
                let delta = lastTranslation - translation.y
                lastTranslation = translation.y
                defer { lastOffset = scroll.contentOffset }
                guard verticalDrag, abs(delta) > 0.001 else { return }
                let minimum = -scroll.adjustedContentInset.top
                let previousOffset = blocking ? lockedOffset : lastOffset
                // 下拉先让列表回顶，只有跨过顶部的剩余手指距离用于展开。
                let requested = VideoScrollHandoff.playerDelta(delta, offset: previousOffset.y, minimum: minimum)
                guard abs(requested) > 0.001, canConsume?(requested) == true else {
                    if blocking {
                        blocking = false
                        scroll.contentOffset.y = max(minimum, previousOffset.y + delta)
                    }
                    return
                }
                blocking = true
                lockedOffset = CGPoint(x: previousOffset.x, y: delta < 0 ? minimum : previousOffset.y)
                let used = consume?(requested) ?? 0
                consumed = consumed || abs(used) > 0
                if canConsume?(requested) != true || abs(used - requested) > 0.01 {
                    blocking = false
                    // 到达任一端点后，剩余位移归还给原生列表。
                    scroll.contentOffset.y = max(minimum, lockedOffset.y + requested - used)
                } else {
                    moved(scroll, old: lockedOffset)
                }
            case .ended:
                // 松手时列表可能尚未回顶。此时也要接管朝顶部的惯性，
                // 否则原生减速到顶后无法将剩余位移交给播放器。
                let returnsToPlayer = verticalDrag && velocity.y > 0 && canConsume?(-1) == true
                if (blocking && consumed) || returnsToPlayer {
                    if !blocking {
                        lockedOffset = scroll.contentOffset
                        lockedOffset.y = max(lockedOffset.y, -scroll.adjustedContentInset.top)
                    }
                    blocking = true
                    momentum = -velocity.y
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
            advanceMomentum(elapsed: dt)
        }

        /// 手指位移与惯性使用相同的交接顺序；拆出时间步以验证松手后的行为。
        func advanceMomentum(elapsed dt: TimeInterval) {
            guard let scroll, displayLink != nil, blocking, dt.isFinite, dt > 0 else { return }
            // UIScrollView 的 decelerationRate 是每毫秒速度保留比例。
            let rate = Double(scroll.decelerationRate.rawValue)
            let decay = pow(rate, dt * 1000)
            let distance = momentum * CGFloat((decay - 1) / (1000 * log(rate)))
            momentum *= CGFloat(decay)
            let minimum = -scroll.adjustedContentInset.top
            let requested = VideoScrollHandoff.playerDelta(distance, offset: lockedOffset.y, minimum: minimum)
            let used = canConsume?(requested) == true ? (consume?(requested) ?? 0) : 0
            let remainder = distance - used
            if abs(remainder) > 0.01 {
                let maximum = max(minimum, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                let proposed = lockedOffset.y + remainder
                lockedOffset.y = min(max(proposed, minimum), maximum)
                if abs(proposed - lockedOffset.y) > 0.01 { momentum = 0 }
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

/// 正值上滑收缩；负值下拉只有越过列表顶部的部分才能展开播放器。
enum VideoScrollHandoff {
    static func playerDelta(_ delta: CGFloat, offset: CGFloat, minimum: CGFloat) -> CGFloat {
        guard delta.isFinite, offset.isFinite, minimum.isFinite else { return 0 }
        return delta < 0 ? min(0, delta + max(0, offset - minimum)) : delta
    }
}
