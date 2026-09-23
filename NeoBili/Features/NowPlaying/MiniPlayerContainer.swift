import SwiftUI
import UIKit

/// 移动发生在固定父坐标中的 UIKit 容器，拖动帧不重建 SwiftUI 内容或视频布局。
struct MiniPlayerContainer<Content: View>: UIViewControllerRepresentable {
    let content: Content
    let aspectRatio: Double?
    let anchor: CGPoint
    let reduceMotion: Bool
    let onAnchorChange: (CGPoint) -> Void

    func makeUIViewController(context: Context) -> MiniPlayerContainerController<Content> {
        let controller = MiniPlayerContainerController(content: content)
        controller.configure(aspectRatio: aspectRatio, anchor: anchor, reduceMotion: reduceMotion,
                             onAnchorChange: onAnchorChange)
        return controller
    }

    func updateUIViewController(_ controller: MiniPlayerContainerController<Content>, context: Context) {
        controller.host.rootView = content
        controller.configure(aspectRatio: aspectRatio, anchor: anchor, reduceMotion: reduceMotion,
                             onAnchorChange: onAnchorChange)
    }

    static func dismantleUIViewController(_ controller: MiniPlayerContainerController<Content>, coordinator: ()) {
        controller.stopMotion()
        controller.onAnchorChange = nil
    }
}

@MainActor
final class MiniPlayerContainerController<Content: View>: UIViewController {
    let host: UIHostingController<Content>
    var onAnchorChange: ((CGPoint) -> Void)?
    private var aspectRatio: Double?
    private var anchor = CGPoint(x: 1, y: 1)
    private var reduceMotion = false
    private var movementBounds = CGRect.zero
    private var windowSize = CGSize.zero
    private var dragOrigin = CGPoint.zero
    private var dragTranslation = CGPoint.zero
    private var isDragging = false
    private var anchorNeedsLayout = true
    private var animator: UIViewPropertyAnimator?

    init(content: Content) {
        host = UIHostingController(rootView: content)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() { view = MiniPlayerPassthroughView() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        addChild(host)
        host.view.backgroundColor = .clear
        host.view.clipsToBounds = false
        host.safeAreaRegions = []
        view.addSubview(host.view)
        host.didMove(toParent: self)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.maximumNumberOfTouches = 1
        host.view.addGestureRecognizer(pan)
    }

    func configure(aspectRatio: Double?, anchor: CGPoint, reduceMotion: Bool,
                   onAnchorChange: @escaping (CGPoint) -> Void) {
        let needsLayout = self.aspectRatio != aspectRatio || self.anchor != anchor
        anchorNeedsLayout = anchorNeedsLayout || self.anchor != anchor
        self.aspectRatio = aspectRatio
        self.anchor = anchor
        self.onAnchorChange = onAnchorChange
        if reduceMotion && !self.reduceMotion {
            stopMotion()
            anchorNeedsLayout = true
            viewIfLoaded?.setNeedsLayout()
        }
        self.reduceMotion = reduceMotion
        if needsLayout { viewIfLoaded?.setNeedsLayout() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.safeAreaLayoutGuide.layoutFrame.insetBy(dx: 12, dy: 12)
        let preferredSize = MiniPlayerLayout.size(in: bounds.size, aspectRatio: aspectRatio)
        let size = MiniPlayerLayout.fittedSize(preferredSize, in: bounds)
        guard bounds != movementBounds || size != windowSize || anchorNeedsLayout else { return }
        stopMotion()
        let visibleCenter = host.view.center
        movementBounds = bounds
        windowSize = size
        anchorNeedsLayout = false
        host.view.bounds = CGRect(origin: .zero, size: size)
        if isDragging {
            host.view.center = MiniPlayerLayout.clampedCenter(visibleCenter, size: size, in: bounds)
            dragOrigin = CGPoint(x: host.view.center.x - dragTranslation.x,
                                 y: host.view.center.y - dragTranslation.y)
        } else {
            host.view.center = MiniPlayerLayout.center(anchor: anchor, size: size, in: bounds)
        }
    }

    /// 必须在停止 animator 前读取显示层；model layer 已经提前处于终点。
    func stopMotion() {
        guard let animator else { return }
        let visibleCenter = host.view.layer.presentation()?.position ?? host.view.center
        animator.stopAnimation(true)
        self.animator = nil
        UIView.performWithoutAnimation { host.view.center = visibleCenter }
    }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        switch gesture.state {
        case .began:
            stopMotion()
            isDragging = true
            dragOrigin = host.view.center
            move(by: translation)
        case .changed:
            guard isDragging else { return }
            move(by: translation)
        case .ended:
            guard isDragging else { return }
            isDragging = false
            settle(velocity: gesture.velocity(in: view))
        case .cancelled, .failed:
            guard isDragging else { return }
            isDragging = false
            settle(velocity: .zero)
        default: break
        }
    }

    private func move(by translation: CGPoint) {
        dragTranslation = translation
        let center = CGPoint(x: dragOrigin.x + translation.x, y: dragOrigin.y + translation.y)
        UIView.performWithoutAnimation {
            host.view.center = MiniPlayerLayout.clampedCenter(center, size: windowSize, in: movementBounds)
        }
    }

    private func settle(velocity: CGPoint) {
        let start = host.view.center
        anchor = MiniPlayerLayout.restingAnchor(center: start, velocity: velocity, size: windowSize, in: movementBounds)
        let destination = MiniPlayerLayout.center(anchor: anchor, size: windowSize, in: movementBounds)
        onAnchorChange?(anchor)
        guard !reduceMotion, hypot(destination.x - start.x, destination.y - start.y) > 0.5 else {
            host.view.center = destination
            return
        }
        let timing = UISpringTimingParameters(dampingRatio: 1,
            initialVelocity: MiniPlayerLayout.springVelocity(velocity, from: start, to: destination))
        let animator = UIViewPropertyAnimator(duration: 0.38, timingParameters: timing)
        animator.addAnimations { [weak self] in self?.host.view.center = destination }
        animator.addCompletion { [weak self, weak animator] _ in
            guard let self, self.animator === animator else { return }
            self.animator = nil
        }
        self.animator = animator
        animator.startAnimation()
    }
}

/// 空白处完全透传，保留列表滚动、标签栏和 SwiftUI 原生按钮的点击行为。
private final class MiniPlayerPassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        return result === self ? nil : result
    }
}
