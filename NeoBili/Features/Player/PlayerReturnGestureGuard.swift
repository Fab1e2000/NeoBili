import SwiftUI
import UIKit

/// 只拒绝从播放器内起手的原生返回手势，保留内容区的系统转场。
struct PlayerReturnGestureGuard: UIViewRepresentable {
    var enabled: Bool

    func makeUIView(context: Context) -> RegionView { RegionView() }

    func updateUIView(_ view: RegionView, context: Context) {
        view.enabled = enabled
        view.install()
    }

    static func dismantleUIView(_ view: RegionView, coordinator: ()) { view.detach() }

    final class RegionView: UIView {
        var enabled = true
        private var gates: [DelegateGate] = []

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { detach() } else { install() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            // 系统转场容器可能晚于播放器加入层级；布局时同步，不进行轮询。
            install()
        }

        func install() {
            guard window != nil else { return }
            var ancestors: [UIView] = []
            var next = superview
            while let view = next {
                ancestors.append(view)
                next = view.superview
            }
            let recognizers = ancestors.flatMap { view in
                (view.gestureRecognizers ?? []).filter {
                    // 不碰滚动容器、播放器内部的控件以及 SwiftUI 的拖动识别器。
                    !(view is UIScrollView)
                        && ($0 is UIPanGestureRecognizer || $0 is UIPinchGestureRecognizer)
                }
            }
            gates.removeAll { gate in
                guard let recognizer = gate.recognizer,
                      recognizers.contains(where: { $0 === recognizer }),
                      recognizer.delegate === gate else {
                    gate.restore()
                    return true
                }
                return false
            }
            for recognizer in recognizers where !gates.contains(where: { $0.recognizer === recognizer }) {
                let gate = DelegateGate(region: self, recognizer: recognizer)
                gates.append(gate)
                recognizer.delegate = gate
            }
        }

        func containsInteraction(at point: CGPoint) -> Bool {
            guard enabled, window != nil, bounds.contains(point), !bounds.isEmpty else { return false }
            var ancestor: UIView? = self
            while let view = ancestor {
                if view.isHidden || view.alpha < 0.01 { return false }
                ancestor = view.superview
            }
            return true
        }

        func detach() {
            gates.forEach { $0.restore() }
            gates.removeAll()
        }
    }

    /// 转发原代理的全部可选行为，只在接收触摸时添加区域过滤。
    final class DelegateGate: NSObject, UIGestureRecognizerDelegate {
        weak var region: RegionView?
        weak var recognizer: UIGestureRecognizer?
        // NSObject 的代理查询没有 actor 标注；该引用只在初始化时写入。
        nonisolated(unsafe) private weak var original: (any UIGestureRecognizerDelegate)?

        init(region: RegionView, recognizer: UIGestureRecognizer) {
            self.region = region
            self.recognizer = recognizer
            original = recognizer.delegate
            super.init()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if let region, region.containsInteraction(at: touch.location(in: region)) { return false }
            return original?.gestureRecognizer?(gestureRecognizer, shouldReceive: touch) ?? true
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (original?.responds(to: selector) ?? false)
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            if original?.responds(to: selector) == true { return original }
            return super.forwardingTarget(for: selector)
        }

        func restore() {
            if let recognizer, recognizer.delegate === self { recognizer.delegate = original }
        }
    }
}
