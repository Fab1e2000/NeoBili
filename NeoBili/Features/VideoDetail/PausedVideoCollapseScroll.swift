import SwiftUI
import UIKit

/// Shared geometry only. Each native list retains its own scroll position and clock.
struct VideoScrollContext {
    let minimumContentHeight: CGFloat
    let reservation: CGFloat
    let distance: @MainActor () -> CGFloat
    let isActive: @MainActor (VideoPageSection) -> Bool
}

extension EnvironmentValues {
    @Entry var videoScrollContext: VideoScrollContext?
}

struct PausedVideoCollapseScroll: UIViewRepresentable {
    let consume: (CGFloat) -> CGFloat
    let end: () -> Void
    let canConsume: (CGFloat) -> Bool
    var canContinue: () -> Bool = { true }
    var section: VideoPageSection = .comments
    @Environment(\.videoScrollContext) private var geometry

    func makeUIView(context: Context) -> Observer { Observer() }
    func updateUIView(_ view: Observer, context: Context) {
        view.consume = consume; view.end = end; view.canConsume = canConsume
        view.configure(geometry, page: section, ownsInsets: false)
        view.attach()
        DispatchQueue.main.async { [weak view] in view?.attach() }
    }
    static func dismantleUIView(_ view: Observer, coordinator: ()) { view.detach() }

    /// Like a smooth pager, the selected UIScrollView owns drag and deceleration.
    /// Reading its offset never locks it or creates another animation clock.
    final class Observer: UIView {
        var consume: ((CGFloat) -> CGFloat)?
        var end: (() -> Void)?
        var canConsume: ((CGFloat) -> Bool)?
        private weak var scroll: UIScrollView?
        private var geometry: VideoScrollContext?
        private var page = VideoPageSection.comments
        private var ownsInsets = false
        private var originalInsets = UIEdgeInsets.zero
        private var appliedInsets = UIEdgeInsets.zero
        private var offsetObservation: NSKeyValueObservation?
        private var insetObservation: NSKeyValueObservation?
        private var sizeObservation: NSKeyValueObservation?
        private var correcting = false
        private var representedDistance: CGFloat = 0
        private var lastOffset: CGFloat = 0
        private(set) var readingOffset: CGFloat = 0

        func configure(_ geometry: VideoScrollContext?, page: VideoPageSection, ownsInsets: Bool) {
            self.geometry = geometry; self.page = page; self.ownsInsets = ownsInsets
            synchronize()
        }
        override func didMoveToWindow() { super.didMoveToWindow(); attach() }
        override func didMoveToSuperview() { super.didMoveToSuperview(); attach() }
        override func layoutSubviews() { super.layoutSubviews(); attach() }

        func attach() {
            var ancestor = superview
            while let view = ancestor {
                if let target = view as? UIScrollView {
                    guard scroll !== target else { synchronize(); return }
                    detach()
                    scroll = target; originalInsets = target.contentInset
                    readingOffset = max(0, target.contentOffset.y + target.adjustedContentInset.top)
                    lastOffset = target.contentOffset.y + target.adjustedContentInset.top
                    synchronize()
                    offsetObservation = target.observe(\.contentOffset, options: [.new]) { [weak self] target, _ in
                        MainActor.assumeIsolated { self?.moved(target) }
                    }
                    insetObservation = target.observe(\.contentInset, options: [.old, .new]) { [weak self] target, change in
                        MainActor.assumeIsolated {
                            guard let self, !self.correcting else { return }
                            if self.ownsInsets {
                                var native = target.contentInset
                                if native.top == self.appliedInsets.top { native.top = self.originalInsets.top }
                                if native.bottom == self.appliedInsets.bottom { native.bottom = self.originalInsets.bottom }
                                self.originalInsets = native
                            }
                            self.synchronize()
                        }
                    }
                    sizeObservation = target.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
                        MainActor.assumeIsolated {
                            guard let self, self.ownsInsets, !self.correcting else { return }
                            self.synchronize()
                        }
                    }
                    return
                }
                ancestor = view.superview
            }
        }

        private func synchronize() {
            guard let scroll, let geometry else { return }
            correcting = true
            if ownsInsets {
                var inset = originalInsets; inset.top += geometry.reservation
                inset.bottom += max(0, geometry.minimumContentHeight - scroll.contentSize.height - originalInsets.bottom)
                appliedInsets = inset
                if scroll.contentInset != inset { scroll.contentInset = inset }
            }
            if geometry.isActive(page) {
                let nextDistance = geometry.distance()
                let target = readingOffset + nextDistance - scroll.adjustedContentInset.top
                let normalized = scroll.contentOffset.y + scroll.adjustedContentInset.top
                let isTopBounce = (scroll.isDragging || scroll.isDecelerating)
                    && normalized < nextDistance && readingOffset == 0
                    && nextDistance == representedDistance
                // Identical offset writes also cancel UIScrollView deceleration.
                if !isTopBounce, abs(target - scroll.contentOffset.y) > 0.5 {
                    scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: target), animated: false)
                }
                representedDistance = nextDistance
            }
            lastOffset = scroll.contentOffset.y + scroll.adjustedContentInset.top
            correcting = false
        }

        private func moved(_ target: UIScrollView) {
            guard !correcting, let geometry else { return }
            let offset = target.contentOffset.y + target.adjustedContentInset.top
            let delta = offset - lastOffset
            lastOffset = offset
            let userDriven = target.isDragging || target.isDecelerating
            if geometry.isActive(page), userDriven, !horizontalPagerIsMoving() {
                let distance = geometry.distance()
                let requested = delta > 0 ? min(delta, max(0, offset - distance)) : min(0, offset - distance)
                if abs(requested) > 0.001, canConsume?(requested) == true {
                    _ = consume?(requested)
                }
                representedDistance = geometry.distance()
            }
            readingOffset = max(0, offset - representedDistance)
        }

        private func horizontalPagerIsMoving() -> Bool {
            var parent = scroll?.superview
            while let view = parent {
                if let pager = view as? UIScrollView, pager.contentSize.width > pager.bounds.width + 1,
                   pager.isDragging || pager.isDecelerating { return true }
                parent = view.superview
            }
            return false
        }

        func logicalOffset(for target: UIScrollView) -> CGFloat {
            correcting ? readingOffset : max(0, target.contentOffset.y + target.adjustedContentInset.top - representedDistance)
        }

        func detach() {
            offsetObservation?.invalidate(); insetObservation?.invalidate(); sizeObservation?.invalidate()
            offsetObservation = nil; insetObservation = nil; sizeObservation = nil
            if ownsInsets, let scroll { scroll.contentInset = originalInsets }
            scroll = nil; representedDistance = 0
        }
    }
}

/// Positive travel collapses the header; negative travel expands only at the list top.
enum VideoScrollHandoff {
    static func playerDelta(_ delta: CGFloat, offset: CGFloat, minimum: CGFloat) -> CGFloat {
        guard delta.isFinite, offset.isFinite, minimum.isFinite else { return 0 }
        return delta < 0 ? min(0, delta + max(0, offset - minimum)) : delta
    }
}

/// Fixed list canvas inside a persistent native viewport. UIKit rejects touches
/// outside the visible bounds even on runtimes where SwiftUI clipping only draws.
struct VideoScrollCanvas<Content: View>: View {
    let height: CGFloat
    let content: Content
    var body: some View {
        GeometryReader { geometry in
            VideoCanvasViewport(content: content, canvasSize: CGSize(width: geometry.size.width, height: height))
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

@MainActor @Observable
private final class VideoCanvasState<Content: View> {
    var content: Content
    var values: EnvironmentValues
    var size: CGSize
    init(content: Content, values: EnvironmentValues, size: CGSize) {
        self.content = content; self.values = values; self.size = size
    }
}

private struct VideoCanvasContent<Content: View>: View {
    let state: VideoCanvasState<Content>
    var body: some View {
        state.content.environment(\.self, state.values).frame(width: state.size.width, height: state.size.height)
    }
}

private struct VideoCanvasViewport<Content: View>: UIViewControllerRepresentable {
    let content: Content
    let canvasSize: CGSize
    func makeUIViewController(context: Context) -> CanvasController<Content> {
        CanvasController(content: content, values: context.environment, size: canvasSize)
    }
    func updateUIViewController(_ controller: CanvasController<Content>, context: Context) {
        withTransaction(context.transaction) {
            controller.state.content = content
            controller.state.values = context.environment
            if controller.state.size != canvasSize { controller.state.size = canvasSize }
        }
        controller.canvasSize = canvasSize
        controller.layoutCanvas()
    }
}

private final class CanvasController<Content: View>: UIViewController {
    let host: UIHostingController<VideoCanvasContent<Content>>
    let state: VideoCanvasState<Content>
    var canvasSize: CGSize
    init(content: Content, values: EnvironmentValues, size: CGSize) {
        let state = VideoCanvasState(content: content, values: values, size: size)
        self.state = state
        host = UIHostingController(rootView: VideoCanvasContent(state: state))
        canvasSize = size
        super.init(nibName: nil, bundle: nil)
        host.safeAreaRegions = []
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.clipsToBounds = true
        addChild(host)
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        host.didMove(toParent: self)
        layoutCanvas()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutCanvas()
    }
    func layoutCanvas() {
        guard isViewLoaded else { return }
        let frame = CGRect(x: 0, y: view.bounds.height - canvasSize.height,
                           width: canvasSize.width, height: canvasSize.height)
        if host.view.frame != frame { host.view.frame = frame }
    }
}
