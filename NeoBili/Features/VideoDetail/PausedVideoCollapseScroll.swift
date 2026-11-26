import NeoBiliDomain
import SwiftUI
import UIKit

/// Shared geometry only. Each native list retains its own scroll position and clock.
@Observable final class VideoScrollContext {
    var minimumContentHeight: CGFloat
    var reservation: CGFloat
    var enabled = true
    let distance: @MainActor () -> CGFloat
    private let selected: @MainActor (VideoPageSection) -> Bool

    init(minimumContentHeight: CGFloat, reservation: CGFloat, distance: @escaping @MainActor () -> CGFloat,
         isActive: @escaping @MainActor (VideoPageSection) -> Bool) {
        self.minimumContentHeight = minimumContentHeight
        self.reservation = reservation
        self.distance = distance
        self.selected = isActive
    }

    @MainActor func isActive(_ page: VideoPageSection) -> Bool { enabled && selected(page) }

    @MainActor var indicatorTopInset: CGFloat { max(0, reservation - distance()) }
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
        private var originalIndicatorTop: CGFloat = 0
        private var appliedInsets = UIEdgeInsets.zero
        private var offsetObservation: NSKeyValueObservation?
        private var insetObservation: NSKeyValueObservation?
        private var indicatorObservation: NSKeyValueObservation?
        private var sizeObservation: NSKeyValueObservation?
        private var correcting = false
        private var representedDistance: CGFloat = 0
        private var lastOffset: CGFloat = 0
        private(set) var readingOffset: CGFloat = 0

        func configure(_ geometry: VideoScrollContext?, page: VideoPageSection, ownsInsets: Bool) {
            guard self.geometry !== geometry || self.page != page || self.ownsInsets != ownsInsets else { return }
            setNeedsUpdateProperties()
            self.geometry = geometry; self.page = page; self.ownsInsets = ownsInsets
            synchronize()
        }
        override func didMoveToWindow() { super.didMoveToWindow(); attach() }
        override func didMoveToSuperview() { super.didMoveToSuperview(); attach() }
        // UIKit tracks observable reads in updateProperties. Reconcile external
        // playback changes and page switches without updating either list's data.
        override func updateProperties() {
            super.updateProperties()
            synchronize()
        }
        override func layoutSubviews() { super.layoutSubviews(); attach() }

        func attach() {
            var ancestor = superview
            while let view = ancestor {
                if let target = view as? UIScrollView {
                    guard scroll !== target else { return }
                    detach()
                    scroll = target; originalInsets = target.contentInset
                    originalIndicatorTop = target.verticalScrollIndicatorInsets.top
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
                    indicatorObservation = target.observe(\.verticalScrollIndicatorInsets, options: [.new]) { [weak self] _, _ in
                        MainActor.assumeIsolated { self?.synchronizeIndicator() }
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
            synchronizeIndicator()
            if geometry.isActive(page) {
                let nextDistance = geometry.distance()
                let target = readingOffset + nextDistance - scroll.adjustedContentInset.top
                let normalized = scroll.contentOffset.y + scroll.adjustedContentInset.top
                let isTopBounce = (scroll.isDragging || scroll.isDecelerating || scroll.refreshControl?.isRefreshing == true)
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
            synchronizeIndicator()
        }

        /// The fixed canvas extends behind the player. Keep the thumb in its
        /// visible viewport, including when SwiftUI refreshes native insets.
        private func synchronizeIndicator() {
            guard let scroll, let geometry else { return }
            let top = originalIndicatorTop + geometry.indicatorTopInset
            if scroll.verticalScrollIndicatorInsets.top != top {
                scroll.verticalScrollIndicatorInsets.top = top
            }
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
            indicatorObservation?.invalidate(); indicatorObservation = nil
            if let scroll {
                if ownsInsets { scroll.contentInset = originalInsets }
                if geometry != nil {
                    scroll.verticalScrollIndicatorInsets.top = originalIndicatorTop
                }
            }
            scroll = nil; representedDistance = 0
        }
    }
}

/// A native clipping viewport with no scrolling axis of its own. Its content
/// occupies exactly one viewport; the taller page canvas overflows upwards.
/// The inner scroll views keep their own gestures, environments and offsets.
struct VideoScrollCanvas<Content: View>: View {
    let height: CGFloat
    let content: Content

    var body: some View {
        ScrollView([]) {
            Color.clear
                .containerRelativeFrame([.horizontal, .vertical])
                .overlay(alignment: .bottom) {
                    content.frame(height: height)
                }
                .contentShape(.interaction, Rectangle())
        }
        .contentMargins(0, for: .scrollContent)
    }
}
