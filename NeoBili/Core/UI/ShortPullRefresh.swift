import SwiftUI
import UIKit

enum HomeRefreshSettings {
    static let storageKey = "neobili.homeRefreshDistance"
    static let defaultDistance = 70.0
    static let range = 40.0...140.0
    static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : defaultDistance
    }
}

/// 阈值使用手指的实际位移，不使用经过系统回弹阻尼后的内容位移。
struct ShortPullState {
    private(set) var eligible = false
    private(set) var distance: CGFloat = 0
    private(set) var armed = false

    mutating func begin(atTop: Bool) {
        eligible = atTop
        distance = 0
        armed = false
    }

    mutating func update(x: CGFloat, y: CGFloat, threshold: CGFloat) {
        guard eligible else { return }
        distance = abs(x) > abs(y) ? 0 : max(y, 0)
        armed = distance >= threshold
    }

    mutating func finish(cancelled: Bool) -> Bool {
        let refresh = eligible && armed && !cancelled
        begin(atTop: false)
        return refresh
    }
}

/// 放在 ScrollView 内容里，观察现有 pan 手势；不添加会争抢滚动的新手势。
struct ShortPullRefresh: UIViewRepresentable {
    let threshold: Double
    let enabled: Bool
    let onProgress: (CGFloat, Bool) -> Void
    let onRefresh: () -> Void

    func makeUIView(context: Context) -> ObserverView { ObserverView() }
    func updateUIView(_ view: ObserverView, context: Context) {
        view.threshold = CGFloat(HomeRefreshSettings.clamped(threshold))
        view.enabled = enabled
        view.onProgress = onProgress
        view.onRefresh = onRefresh
        view.attach()
    }
    static func dismantleUIView(_ view: ObserverView, coordinator: ()) { view.detach() }

    final class ObserverView: UIView {
        var threshold: CGFloat = 70
        var enabled = true
        var onProgress: ((CGFloat, Bool) -> Void)?
        var onRefresh: (() -> Void)?
        private weak var scroll: UIScrollView?
        private var state = ShortPullState()
        private let haptic = UIImpactFeedbackGenerator(style: .light)

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
                    return
                }
                ancestor = view.superview
            }
        }

        func detach() {
            scroll?.panGestureRecognizer.removeTarget(self, action: #selector(panned(_:)))
            scroll = nil
            state.begin(atTop: false)
        }

        @objc private func panned(_ gesture: UIPanGestureRecognizer) {
            guard let scroll else { return }
            let translation = gesture.translation(in: scroll.window)
            switch gesture.state {
            case .began:
                state.begin(atTop: enabled && scroll.contentOffset.y + scroll.adjustedContentInset.top <= 1)
                haptic.prepare()
                update(translation)
            case .changed:
                update(translation)
            case .ended:
                update(translation)
                let refresh = state.finish(cancelled: !enabled)
                // 真要刷新时不清零：调用方靠这个值把下拉的淡出接着往下走，
                // 清零会让列表先弹回全不透明再重新淡，看着就是闪一下。
                if !refresh { onProgress?(0, false) }
                if refresh { onRefresh?() }
            case .cancelled, .failed:
                _ = state.finish(cancelled: true)
                onProgress?(0, false)
            default: break
            }
        }

        private func update(_ translation: CGPoint) {
            let previouslyArmed = state.armed
            state.update(x: translation.x, y: translation.y, threshold: threshold)
            if state.armed && !previouslyArmed { haptic.impactOccurred(); haptic.prepare() }
            onProgress?(state.distance, state.armed)
        }
    }
}
