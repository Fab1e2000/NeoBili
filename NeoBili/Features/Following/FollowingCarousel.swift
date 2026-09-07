import SwiftUI
import UIKit

/// 偏好同时供设置页和关注页使用，左右两侧采用相同的命中范围。
enum FollowingSidebarSide: String, CaseIterable, Identifiable {
    case left, right
    static let storageKey = "neobili.followingSidebarSide"
    var id: String { rawValue }
    var title: String { self == .left ? "左侧" : "右侧" }
    var alignment: Alignment { self == .left ? .leading : .trailing }
}

enum FollowingSidebarDwellSettings {
    static let storageKey = "neobili.followingSidebarDwellDuration"
    static let defaultDuration = 0.5
    static let range = 0.1...2.0

    static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : defaultDuration
    }
}

enum FollowingSidebarLayout {
    static let transitionDuration: TimeInterval = 0.24
    static let contentDisplacement: CGFloat = FollowingSidebarShape.width + FollowingSidebarContour.gap
    static let countKey = "neobili.followingSidebarCount"
    static let counts = [5, 7, 9, 11]
    static let defaultCount = 7

    static func count(_ stored: Int) -> Int { counts.contains(stored) ? stored : defaultCount }
    static func height(count: Int, available: CGFloat) -> CGFloat {
        min(CGFloat(Self.count(count)) * 64, max(64, available - 48))
    }

    static func occupiedBounds(count: Int, rowHeight: CGFloat, offset: CGFloat, viewport: CGFloat) -> ClosedRange<CGFloat> {
        let padding = max(40, rowHeight / 2)
        let firstCenter = rowHeight / 2 - offset
        let lastCenter = CGFloat(max(0, count - 1)) * rowHeight + rowHeight / 2 - offset
        return max(0, min(viewport / 2 - 30, firstCenter - padding))...min(viewport, max(viewport / 2 + 30, lastCenter + padding))
    }
}

/// A：边缘头像入口；B：可上下滚动的头像列表。仅在停稳或收起时提交筛选。
struct FollowingCarousel: View {
    let items: [FollowingSelection]
    @Binding var focusedID: FollowingSelection.ID
    let side: FollowingSidebarSide
    @Binding var isExpanded: Bool
    let onSettled: (FollowingSelection.ID) -> Void
    let onOpenUp: (FollowedUp) -> Void
    let interactiveProgress: CGFloat?
    let onCloseSwipe: (CGFloat) -> Void
    let onCloseSwipeEnd: (CGFloat) -> Void

    // 每次打开独立的滚动会话，旧 ScrollView 的退出回调不能改变新会话。
    @State private var sessionID = UUID()
    @State private var expandedIDs: [FollowingSelection.ID] = []
    @AppStorage(FollowingSidebarLayout.countKey) private var visibleCount = FollowingSidebarLayout.defaultCount
    @State private var isPressSelecting = false
    @State private var isBackdropDragging = false
    @State private var isBackdropClosing = false
    @State private var scrollController: FollowingAvatarScrollController

    init(items: [FollowingSelection], focusedID: Binding<FollowingSelection.ID>, side: FollowingSidebarSide,
         isExpanded: Binding<Bool>, onSettled: @escaping (FollowingSelection.ID) -> Void,
         onOpenUp: @escaping (FollowedUp) -> Void,
         interactiveProgress: CGFloat? = nil,
         onCloseSwipe: @escaping (CGFloat) -> Void = { _ in },
         onCloseSwipeEnd: @escaping (CGFloat) -> Void = { _ in },
         controller: FollowingAvatarScrollController? = nil) {
        self.items = items
        _focusedID = focusedID
        self.side = side
        _isExpanded = isExpanded
        self.onSettled = onSettled
        self.onOpenUp = onOpenUp
        self.interactiveProgress = interactiveProgress
        self.onCloseSwipe = onCloseSwipe
        self.onCloseSwipeEnd = onCloseSwipeEnd
        _scrollController = State(initialValue: controller ?? FollowingAvatarScrollController())
    }

    private var displayedItems: [FollowingSelection] {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let known = Set(expandedIDs)
        return expandedIDs.compactMap { byID[$0] } + items.filter { !known.contains($0.id) }
    }

    private var focusedItem: FollowingSelection {
        items.first { $0.id == focusedID } ?? .all
    }

    var body: some View {
        GeometryReader { geometry in
            let height = FollowingSidebarLayout.height(count: visibleCount, available: geometry.size.height)
            let rowHeight = height / CGFloat(FollowingSidebarLayout.count(visibleCount))
            ZStack(alignment: side.alignment) {
                if isExpanded {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 8, coordinateSpace: .global)
                                .onChanged { value in
                                    if !isBackdropDragging,
                                       isBackdropClosing || (value.translation.width < 0 && abs(value.translation.width) > abs(value.translation.height) * 1.3) {
                                        isBackdropClosing = true
                                        onCloseSwipe(value.translation.width)
                                        return
                                    }
                                    guard isBackdropDragging || abs(value.translation.height) > abs(value.translation.width) else { return }
                                    if !isBackdropDragging {
                                        isBackdropDragging = true
                                        scrollController.beginExternalDrag()
                                    }
                                    scrollController.moveExternalDrag(
                                        translation: value.translation.height,
                                        velocity: value.velocity.height
                                    )
                                }
                                .onEnded { value in
                                    if isBackdropClosing {
                                        isBackdropClosing = false
                                        onCloseSwipe(value.translation.width)
                                        onCloseSwipeEnd(value.velocity.width)
                                        return
                                    }
                                    guard isBackdropDragging else { return }
                                    scrollController.endExternalDrag()
                                    isBackdropDragging = false
                                }
                                .exclusively(before: TapGesture().onEnded { collapse() })
                        )
                        .accessibilityLabel("收起关注列表")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { collapse() }
                        .accessibilityIdentifier("following.sidebar.dismiss")

                }
                // 同一份原生列表同时承载 A/B，收起不会销毁或复制头像。
                expandedRail(height: height, rowHeight: rowHeight)
                    .allowsHitTesting(isExpanded)
                    .accessibilityHidden(!isExpanded)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 12, coordinateSpace: .global)
                            .onChanged { value in
                                guard isExpanded,
                                      isBackdropClosing || (value.translation.width < 0 && abs(value.translation.width) > abs(value.translation.height) * 1.3) else { return }
                                isBackdropClosing = true
                                onCloseSwipe(value.translation.width)
                            }
                            .onEnded { value in
                                guard isBackdropClosing else { return }
                                isBackdropClosing = false
                                onCloseSwipe(value.translation.width)
                                onCloseSwipeEnd(value.velocity.width)
                            }
                    )
                ZStack {
                    FollowingHandleTouchSurface(
                        enabled: !isExpanded || isPressSelecting,
                        onBegin: {
                            expand()
                            isPressSelecting = true
                            scrollController.beginExternalDrag()
                        },
                        onMove: { delta, velocity in
                            scrollController.moveExternalDrag(translation: delta, velocity: velocity)
                        },
                        onEnd: {
                            scrollController.endExternalDrag()
                            isPressSelecting = false
                        }
                    )
                }
                .frame(width: 44, height: 76)
                .allowsHitTesting(!isExpanded || isPressSelecting)
                .accessibilityHidden(isExpanded)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("展开关注列表，\(focusedItem.title)")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { expand() }
                .accessibilityIdentifier("following.sidebar.expand")

            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: side.alignment)
            .clipped()
        }
        .onChange(of: items.map(\.id)) { _, ids in
            if !ids.contains(focusedID) {
                focusedID = .all
                // 被取消关注的选中项消失时重建会话，以「全部」重新定位。
                sessionID = UUID()
                onSettled(.all)
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                expandedIDs = items.map(\.id)
            } else {
                isBackdropDragging = false
                isBackdropClosing = false
                isPressSelecting = false
                scrollController.stop()
            }
        }
    }

    private func expandedRail(height: CGFloat, rowHeight: CGFloat) -> some View {
        let session = sessionID
        return FollowingExpandedCarousel(
            items: displayedItems,
            initialID: focusedID,
            side: side,
            height: height,
            rowHeight: rowHeight,
            isExpanded: isExpanded,
            interactiveProgress: interactiveProgress,
            controller: scrollController,
            onFocus: { id in
                guard isExpanded, sessionID == session else { return }
                focusedID = id
            },
            onSettled: { id in
                guard isExpanded, sessionID == session else { return }
                onSettled(id)
            },
            onOpenUp: { up in
                collapse()
                onOpenUp(up)
            }
        )
        .id(session)
    }

    private func expand() {
        guard !isExpanded else { return }
        expandedIDs = items.map(\.id)
        isExpanded = true
    }

    private func collapse() {
        onSettled(focusedID)
        isExpanded = false
    }
}

/// 原生列表负责唯一一份头像布局；玻璃只放在背景，不参与头像变换。
private struct FollowingExpandedCarousel: View {
    let items: [FollowingSelection]
    let initialID: FollowingSelection.ID
    let side: FollowingSidebarSide
    let height: CGFloat
    let rowHeight: CGFloat
    let isExpanded: Bool
    let interactiveProgress: CGFloat?
    let controller: FollowingAvatarScrollController
    let onFocus: (FollowingSelection.ID) -> Void
    let onSettled: (FollowingSelection.ID) -> Void
    let onOpenUp: (FollowedUp) -> Void
    @State private var titleID: FollowingSelection.ID?
    @State private var alignmentDistance: CGFloat?

    var body: some View {
        let shape = FollowingSidebarShape(side: side)
        GlassEffectContainer(spacing: 0) {
            FollowingAvatarScroll(
                items: items, initialID: initialID, side: side, rowHeight: rowHeight,
                isExpanded: isExpanded, interactiveProgress: interactiveProgress, controller: controller,
                onFocus: { titleID = $0; onFocus($0) },
                onSettled: onSettled, onOpenUp: onOpenUp,
                onAlignment: { alignmentDistance = $0 }
            )
            .frame(width: FollowingSidebarShape.width, height: height)
            .contentShape(shape)
            .overlay(alignment: side == .left ? .trailing : .leading) {
                if isExpanded {
                    Text(items.first { $0.id == (titleID ?? initialID) }?.title ?? "全部动态")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .glassEffect(.regular, in: Capsule())
                        .frame(width: 140)
                        .opacity(Double(interactiveProgress ?? 1))
                        .offset(x: side == .left ? 144 : -144)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .preference(key: FollowingSidebarAlignmentKey.self, value: alignmentDistance)
            .accessibilityIdentifier("following.sidebar.list")
        }
    }
}

/// 零等待触摸识别：从按下到松手始终由同一个 UIView 接收。
private struct FollowingHandleTouchSurface: UIViewRepresentable {
    let enabled: Bool
    let onBegin: () -> Void
    let onMove: (CGFloat, CGFloat) -> Void
    let onEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.press(_:)))
        press.minimumPressDuration = 0
        press.allowableMovement = 16
        view.addGestureRecognizer(press)
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
        view.isUserInteractionEnabled = enabled
    }

    final class Coordinator: NSObject {
        var parent: FollowingHandleTouchSurface
        var startY: CGFloat = 0
        var previousY: CGFloat = 0
        var previousTime: CFTimeInterval = 0
        init(_ parent: FollowingHandleTouchSurface) { self.parent = parent }
        @objc func press(_ gesture: UILongPressGestureRecognizer) {
            let y = gesture.location(in: gesture.view?.window).y
            let now = CACurrentMediaTime()
            switch gesture.state {
            case .began:
                startY = y
                previousY = y
                previousTime = now
                parent.onBegin()
            case .changed:
                let elapsed = max(now - previousTime, 0.001)
                parent.onMove(y - startY, (y - previousY) / elapsed)
                previousY = y
                previousTime = now
            case .ended, .cancelled, .failed:
                // 停住后松手不应继承之前甩动的速度。
                if now - previousTime > 0.1 { parent.onMove(y - startY, 0) }
                parent.onEnd()
            default: break
            }
        }
    }
}

private struct FollowingAvatarScroll: UIViewRepresentable {
    let items: [FollowingSelection]
    let initialID: FollowingSelection.ID
    let side: FollowingSidebarSide
    let rowHeight: CGFloat
    let isExpanded: Bool
    let interactiveProgress: CGFloat?
    let controller: FollowingAvatarScrollController
    let onFocus: (FollowingSelection.ID) -> Void
    let onSettled: (FollowingSelection.ID) -> Void
    let onOpenUp: (FollowedUp) -> Void
    let onAlignment: (CGFloat) -> Void

    func makeCoordinator() -> FollowingAvatarScrollController { controller }
    func makeUIView(context: Context) -> FollowingAvatarGlassView {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        let view = FollowingAvatarCollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.showsVerticalScrollIndicator = false
        view.contentInsetAdjustmentBehavior = .never
        view.decelerationRate = .fast
        view.register(FollowingAvatarCell.self, forCellWithReuseIdentifier: "avatar")
        view.dataSource = controller
        view.delegate = controller
        controller.attach(view)
        view.onLayout = { [weak controller] in controller?.layout() }
        let container = FollowingAvatarGlassView(collection: view)
        controller.glassView = container
        return container
    }
    func updateUIView(_ view: FollowingAvatarGlassView, context: Context) {
        view.side = side
        view.isUserInteractionEnabled = isExpanded
        view.setNeedsLayout()
        controller.onFocus = onFocus
        controller.onSettled = onSettled
        controller.onOpenUp = onOpenUp
        controller.onAlignment = onAlignment
        controller.configure(items: items, initialID: initialID, side: side, rowHeight: rowHeight, expanded: isExpanded, interactiveProgress: interactiveProgress)
    }
    static func dismantleUIView(_ view: FollowingAvatarGlassView, coordinator: FollowingAvatarScrollController) {
        view.collection.onLayout = nil
        if coordinator.collection === view.collection { coordinator.detach() }
    }
}

/// 头像必须放进玻璃的 contentView，避免跨 SwiftUI/UIKit 合成时被当作背景再次折射。
private final class FollowingAvatarGlassView: UIView {
    let collection: FollowingAvatarCollectionView
    var side: FollowingSidebarSide = .left
    private let glass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
    private let outline = CAShapeLayer()

    init(collection: FollowingAvatarCollectionView) {
        self.collection = collection
        super.init(frame: .zero)
        addSubview(glass)
        glass.contentView.addSubview(collection)
        layer.mask = outline
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        collection.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outline.frame = bounds
        CATransaction.commit()
    }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard super.point(inside: point, with: event),
              let visible = (outline.presentation() as? CAShapeLayer)?.path ?? outline.path else { return false }
        return visible.contains(point)
    }

    func updateExtent(_ occupied: ClosedRange<CGFloat>, progress: CGFloat, animated: Bool, interactive: Bool) {
        guard bounds.height > 0 else { return }
        let collapsed = CGRect(x: side == .left ? -30 : bounds.width - 30, y: bounds.midY - 30, width: 60, height: 60)
        let target = CGRect(x: 0, y: occupied.lowerBound, width: bounds.width, height: occupied.upperBound - occupied.lowerBound)
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * progress }
        let rect = CGRect(x: mix(collapsed.minX, target.minX), y: mix(collapsed.minY, target.minY),
                          width: mix(collapsed.width, target.width), height: mix(collapsed.height, target.height))
        let shape = FollowingSidebarShape(side: side, focusY: bounds.midY - rect.minY,
                                          spineWidth: mix(60, 56), bulge: 32 * progress)
        let path = shape.path(in: rect).cgPath
        let old = (outline.presentation() as? CAShapeLayer)?.path ?? outline.path
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if interactive { outline.removeAnimation(forKey: "expansion") }
        outline.path = path
        CATransaction.commit()
        if animated, let old, !UIAccessibility.isReduceMotionEnabled {
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = old
            animation.toValue = path
            animation.duration = FollowingSidebarLayout.transitionDuration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            outline.add(animation, forKey: "expansion")
        }
    }

}

private final class FollowingAvatarCollectionView: UICollectionView {
    var onLayout: (() -> Void)?
    override func layoutSubviews() { super.layoutSubviews(); onLayout?() }
}

/// 只变换头像自身的宿主，不能变换 UICollectionView 管理 frame 的 contentView。
private final class FollowingAvatarCell: UICollectionViewCell {
    private let host = UIHostingController(rootView: FollowingSidebarAvatar(item: .all, selected: false, size: 40))
    private var item: FollowingSelection = .all
    private var avatarSize: CGFloat = 40
    private var weight: CGFloat = 0
    private var side: FollowingSidebarSide = .left
    private var focusedAppearance = false
    private var expansionProgress: CGFloat = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        host.view.backgroundColor = .clear
        host.view.isUserInteractionEnabled = false
        contentView.addSubview(host.view)
        isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setItem(_ item: FollowingSelection, size: CGFloat) {
        self.item = item
        avatarSize = size
        host.rootView = FollowingSidebarAvatar(item: item, selected: focusedAppearance, size: size)
        accessibilityLabel = item.title
        accessibilityIdentifier = "following.avatar.\(item.id)"
        setNeedsLayout()
    }
    func emphasize(weight: CGFloat, side: FollowingSidebarSide, selected: Bool, progress: CGFloat) {
        self.weight = weight
        self.side = side
        self.expansionProgress = progress
        host.view.alpha = selected ? 1 : progress
        if self.focusedAppearance != selected {
            self.focusedAppearance = selected
            host.rootView = FollowingSidebarAvatar(item: item, selected: selected, size: avatarSize)
        }
        accessibilityTraits = selected ? [.button, .selected] : [.button]
        positionAvatar()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        positionAvatar()
    }
    func stopAppearanceAnimation() { host.view.layer.removeAllAnimations() }

    private func positionAvatar() {
        let expandedX = side == .left ? 28 + 20 * weight : bounds.width - 28 - 20 * weight
        let collapsedX: CGFloat = side == .left ? 0 : bounds.width
        let x = collapsedX + (expandedX - collapsedX) * expansionProgress
        host.view.bounds = CGRect(x: 0, y: 0, width: avatarSize, height: avatarSize)
        host.view.center = CGPoint(x: x, y: bounds.height / 2)
        host.view.transform = CGAffineTransform(scaleX: 1 + 0.5 * weight, y: 1 + 0.5 * weight)
    }
}

/// 普通拖动与长按拖动共享同一个连续 contentOffset 及松手后的弹簧停靠。
@MainActor
final class FollowingAvatarScrollController: NSObject, UICollectionViewDataSource, UICollectionViewDelegate {
    fileprivate weak var collection: FollowingAvatarCollectionView?
    fileprivate weak var glassView: FollowingAvatarGlassView?
    private var expanded = false
    private var expansionChanged = false
    private var interactiveProgress: CGFloat?
    private var expansionProgress: CGFloat = 0
    private var items: [FollowingSelection] = []
    private var side: FollowingSidebarSide = .left
    private var rowHeight: CGFloat = 64
    private var selectedIndex = 0
    private var hasPosition = false
    private var lastSize = CGSize.zero
    private var external = false
    private var dragStartOffset: CGFloat = 0
    private var translation: CGFloat = 0
    private var dragVelocity: CGFloat = 0
    private var releaseVelocity: CGFloat = 0
    private var displayLink: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var target: CGFloat = 0
    private var velocity: CGFloat = 0
    private var reportedID: FollowingSelection.ID?
    private var reportedDistance: CGFloat?
    private let haptic = UISelectionFeedbackGenerator()
    var onFocus: (FollowingSelection.ID) -> Void = { _ in }
    var onSettled: (FollowingSelection.ID) -> Void = { _ in }
    var onOpenUp: (FollowedUp) -> Void = { _ in }
    var onAlignment: (CGFloat) -> Void = { _ in }

    fileprivate func attach(_ view: FollowingAvatarCollectionView) {
        stop()
        collection = view
        items = []
        hasPosition = false
        reportedID = nil
        reportedDistance = nil
        lastSize = .zero
    }
    fileprivate func detach() {
        stop()
        external = false
        collection = nil
        onFocus = { _ in }; onSettled = { _ in }; onAlignment = { _ in }; onOpenUp = { _ in }
    }

    fileprivate func configure(items: [FollowingSelection], initialID: FollowingSelection.ID, side: FollowingSidebarSide, rowHeight: CGFloat, expanded: Bool, interactiveProgress: CGFloat?) {
        guard let collection else { return }
        let changed = self.items != items
        let resized = self.rowHeight != rowHeight || self.side != side
        if !hasPosition || !self.expanded {
            let index = items.firstIndex { $0.id == initialID } ?? 0
            if selectedIndex != index { hasPosition = false }
            selectedIndex = index
        }
        if self.expanded != expanded {
            reportedID = nil
            reportedDistance = nil
            if !expanded { stop(); external = false; hasPosition = false }
        }
        expansionChanged = expansionChanged || self.expanded != expanded || (self.interactiveProgress != nil && interactiveProgress == nil)
        self.interactiveProgress = interactiveProgress
        expansionProgress = min(max(interactiveProgress ?? (expanded ? 1 : 0), 0), 1)
        self.expanded = expanded
        collection.isScrollEnabled = expanded
        self.items = items
        self.side = side
        self.rowHeight = rowHeight
        if let layout = collection.collectionViewLayout as? UICollectionViewFlowLayout {
            let size = CGSize(width: FollowingSidebarShape.width, height: rowHeight)
            if layout.itemSize != size { layout.itemSize = size; layout.invalidateLayout() }
        }
        if changed { UIView.performWithoutAnimation { collection.reloadData() } }
        if resized { lastSize = .zero }
        collection.setNeedsLayout()
    }

    fileprivate func layout() {
        guard let collection, collection.bounds.height > 0, !items.isEmpty else { return }
        if !hasPosition || lastSize != collection.bounds.size {
            let inset = max(0, (collection.bounds.height - rowHeight) / 2)
            collection.contentInset = UIEdgeInsets(top: inset, left: 0, bottom: inset, right: 0)
            hasPosition = true
            lastSize = collection.bounds.size
            let y = CGFloat(selectedIndex) * rowHeight - inset
            collection.setContentOffset(CGPoint(x: 0, y: y), animated: false)
            if external { dragStartOffset = y; applyExternalDrag() }
        }
        render()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { items.count }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "avatar", for: indexPath)
        configureCell(cell, index: indexPath.item)
        return cell
    }
    private func configureCell(_ cell: UICollectionViewCell, index: Int) {
        guard let cell = cell as? FollowingAvatarCell else { return }
        cell.setItem(items[index], size: min(40, rowHeight * 0.625))
    }
    private func render() {
        guard let collection, hasPosition, !items.isEmpty else { return }
        let center = collection.contentOffset.y + collection.bounds.height / 2
        let index = min(items.count - 1, max(0, Int(((center - rowHeight / 2) / rowHeight).rounded())))
        let changed = selectedIndex != index
        selectedIndex = index
        let animate = expansionChanged && interactiveProgress == nil && !UIAccessibility.isReduceMotionEnabled
        expansionChanged = false
        let applyAppearance = {
            for path in collection.indexPathsForVisibleItems {
                guard let cell = collection.cellForItem(at: path) else { continue }
                let weight = max(0, 1 - abs(cell.center.y - center) / self.rowHeight)
                (cell as? FollowingAvatarCell)?.emphasize(weight: weight, side: self.side, selected: path.item == index, progress: self.expansionProgress)
            }
        }
        if animate {
            UIView.animate(withDuration: FollowingSidebarLayout.transitionDuration, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut], animations: applyAppearance)
        } else {
            if interactiveProgress != nil {
                for cell in collection.visibleCells {
                    (cell as? FollowingAvatarCell)?.stopAppearanceAnimation()
                }
            }
            UIView.performWithoutAnimation(applyAppearance)
        }
        let occupied = FollowingSidebarLayout.occupiedBounds(count: items.count, rowHeight: rowHeight,
                                                             offset: collection.contentOffset.y, viewport: collection.bounds.height)
        glassView?.updateExtent(occupied, progress: expansionProgress, animated: animate, interactive: interactiveProgress != nil)
        if changed { haptic.selectionChanged() }
        let id = items[index].id
        let distance = CGFloat(index) * rowHeight + rowHeight / 2 - center
        guard reportedID != id || reportedDistance == nil || abs((reportedDistance ?? 0) - distance) > 0.1 else { return }
        reportedID = id
        reportedDistance = distance
        // 避免 updateUIView / layoutSubviews 中同步修改 SwiftUI 状态。
        DispatchQueue.main.async { [weak self, weak collection] in
            guard let self, let collection, self.collection === collection else { return }
            guard self.items.indices.contains(self.selectedIndex), self.items[self.selectedIndex].id == id else { return }
            self.onFocus(id)
            self.onAlignment(distance)
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) { render() }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { stop(); external = false }
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        releaseVelocity = velocity.y * 1000
        targetContentOffset.pointee = scrollView.contentOffset
    }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
        settle(speed: releaseVelocity)
    }

    func beginExternalDrag() {
        stop()
        external = true
        translation = 0
        dragVelocity = 0
        dragStartOffset = collection?.contentOffset.y ?? 0
    }
    func moveExternalDrag(translation: CGFloat, velocity: CGFloat) {
        guard external else { return }
        self.translation = translation
        dragVelocity = -velocity
        applyExternalDrag()
    }
    private func applyExternalDrag() {
        guard let collection, hasPosition else { return }
        collection.setContentOffset(CGPoint(x: 0, y: clamped(dragStartOffset - translation)), animated: false)
    }
    func endExternalDrag() { guard external else { return }; external = false; settle(speed: dragVelocity) }

    private func clamped(_ offset: CGFloat) -> CGFloat {
        guard let collection else { return offset }
        return min(CGFloat(max(0, items.count - 1)) * rowHeight - collection.contentInset.top,
                   max(-collection.contentInset.top, offset))
    }
    private func settle(speed: CGFloat) {
        guard let collection, hasPosition else { return }
        stop()
        let projected = clamped(collection.contentOffset.y + speed * 0.12)
        target = clamped(((projected + collection.contentInset.top) / rowHeight).rounded() * rowHeight - collection.contentInset.top)
        if UIAccessibility.isReduceMotionEnabled {
            collection.setContentOffset(CGPoint(x: 0, y: target), animated: false)
            if items.indices.contains(selectedIndex) { onSettled(items[selectedIndex].id) }
            return
        }
        velocity = speed
        lastTime = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }
    @objc private func tick(_ link: CADisplayLink) {
        guard let collection else { stop(); return }
        let dt = min(1.0 / 30, max(0.001, link.timestamp - lastTime))
        lastTime = link.timestamp
        let delta = target - collection.contentOffset.y
        velocity += (324 * delta - 36 * velocity) * dt
        let offset = clamped(collection.contentOffset.y + velocity * dt)
        collection.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
        if abs(delta) < 0.3 && abs(velocity) < 3 {
            collection.setContentOffset(CGPoint(x: 0, y: target), animated: false)
            stop()
            if items.indices.contains(selectedIndex) { onSettled(items[selectedIndex].id) }
        }
    }
    func stop() { displayLink?.invalidate(); displayLink = nil }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        stop()
        guard items.indices.contains(indexPath.item) else { return }
        let y = CGFloat(indexPath.item) * rowHeight - collectionView.contentInset.top
        collectionView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
        onSettled(items[indexPath.item].id)
    }
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let up = items[indexPath.item].up else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [UIAction(title: "查看 UP 主主页", image: UIImage(systemName: "person.crop.circle")) { _ in self?.onOpenUp(up) }])
        }
    }
}

/// 所有头像与背景共用的胶囊：靠屏幕边缘的一侧保持直线，内侧平滑突出。
/// 选择器与页面凹口共用同一条轮廓，凹口沿法线偏移而非水平平移。
enum FollowingSidebarContour {
    static let spine: CGFloat = 56
    static let bulge: CGFloat = 32
    static let reach: CGFloat = 100
    static let gap: CGFloat = 8

    static func width(at y: CGFloat, base: CGFloat = spine, amplitude: CGFloat = bulge) -> CGFloat {
        base + (abs(y) < reach ? amplitude * (1 + cos(.pi * y / reach)) / 2 : 0)
    }

    static func slope(at y: CGFloat, amplitude: CGFloat = bulge) -> CGFloat {
        abs(y) < reach ? -amplitude * .pi / (2 * reach) * sin(.pi * y / reach) : 0
    }

    static func pageEdge(at y: CGFloat) -> CGPoint {
        let derivative = slope(at: y)
        let normalLength = sqrt(1 + derivative * derivative)
        return CGPoint(x: width(at: y) + gap / normalLength,
                       y: y - gap * derivative / normalLength)
    }
}

struct FollowingSidebarShape: Shape {
    static let width: CGFloat = 88
    let side: FollowingSidebarSide
    var focusY: CGFloat? = nil
    var spineWidth: CGFloat = FollowingSidebarContour.spine
    var bulge: CGFloat = FollowingSidebarContour.bulge

    func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let middle = focusY ?? rect.height / 2
        let base = min(spineWidth, rect.width)
        let amplitude = min(bulge, rect.width - base)
        func width(_ y: CGFloat) -> CGFloat {
            FollowingSidebarContour.width(at: y - middle, base: base, amplitude: amplitude)
        }
        func slope(_ y: CGFloat) -> CGFloat {
            FollowingSidebarContour.slope(at: y - middle, amplitude: amplitude)
        }
        // 圆帽直接接入内侧曲线，而不是用另一层圆角矩形截断曲线。
        var topRadius = min(base / 2, rect.height / 2)
        var bottomRadius = topRadius
        for _ in 0..<6 {
            topRadius = min(width(topRadius) / 2, rect.height / 2)
            bottomRadius = min(width(rect.height - bottomRadius) / 2, rect.height / 2)
        }
        let topY = topRadius
        let bottomY = rect.height - bottomRadius
        let topWidth = width(topY)
        let bottomWidth = width(bottomY)
        let k: CGFloat = 0.55228475
        var path = Path()
        path.move(to: CGPoint(x: 0, y: topY))
        path.addCurve(to: CGPoint(x: topWidth / 2, y: 0),
                      control1: CGPoint(x: 0, y: topY * (1 - k)),
                      control2: CGPoint(x: topWidth / 2 * (1 - k), y: 0))
        path.addCurve(to: CGPoint(x: topWidth, y: topY),
                      control1: CGPoint(x: topWidth / 2 * (1 + k), y: 0),
                      control2: CGPoint(x: topWidth - slope(topY) * topRadius * k, y: topY - topRadius * k))
        // 固定段数和路径拓扑，A/B 及不同高度间可直接插值，不产生尖角。
        for segment in 0..<32 {
            let y0 = topY + (bottomY - topY) * CGFloat(segment) / 32
            let y1 = topY + (bottomY - topY) * CGFloat(segment + 1) / 32
            let step = (y1 - y0) / 3
            path.addCurve(to: CGPoint(x: width(y1), y: y1),
                          control1: CGPoint(x: width(y0) + slope(y0) * step, y: y0 + step),
                          control2: CGPoint(x: width(y1) - slope(y1) * step, y: y1 - step))
        }
        path.addCurve(to: CGPoint(x: bottomWidth / 2, y: rect.height),
                      control1: CGPoint(x: bottomWidth + slope(bottomY) * bottomRadius * k, y: bottomY + bottomRadius * k),
                      control2: CGPoint(x: bottomWidth / 2 * (1 + k), y: rect.height))
        path.addCurve(to: CGPoint(x: 0, y: bottomY),
                      control1: CGPoint(x: bottomWidth / 2 * (1 - k), y: rect.height),
                      control2: CGPoint(x: 0, y: rect.height - bottomRadius * (1 - k)))
        path.closeSubpath()
        if side == .right {
            path = path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.width, ty: 0))
        }
        return path.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}

/// 实际焦点行到视窗中线的距离，也用于真机回归检查重新展开后的定位。
struct FollowingSidebarAlignmentKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() { value = next }
    }
}

private struct FollowingSidebarAvatar: View {
    let item: FollowingSelection
    let selected: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            if let up = item.up {
                BiliImage(url: up.secureAvatarURL).aspectRatio(contentMode: .fill).id(up.mid)
            } else {
                AllDynamicsAvatar()
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(Circle())
        .overlay { Circle().stroke(selected ? Color.accentColor : .white.opacity(0.4), lineWidth: selected ? 2.5 : 1) }
        .overlay(alignment: .topTrailing) {
            if item.up?.hasUpdate == true {
                Circle().fill(.red).frame(width: 10, height: 10)
                    .overlay { Circle().stroke(.background, lineWidth: 2) }
            }
        }
        .scaleEffect(size / 60)
        .frame(width: size, height: size)
    }
}

/// 「全部动态」使用的代码原生品牌头像：三条轨道与节点表示多个 UP
/// 共同组成一条动态流，不依赖额外位图资源。
private struct AllDynamicsAvatar: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.62)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            ZStack {
                orbit(width: 40, height: 17, rotation: 24)
                orbit(width: 40, height: 17, rotation: -24)
                orbit(width: 20, height: 39, rotation: 0)

                Circle()
                    .fill(.white)
                    .frame(width: 7, height: 7)

                Circle()
                    .fill(.white)
                    .frame(width: 5, height: 5)
                    .offset(x: 17, y: -7)

                Circle()
                    .fill(.white.opacity(0.9))
                    .frame(width: 4, height: 4)
                    .offset(x: -14, y: 11)
            }
        }
    }

    private func orbit(width: CGFloat, height: CGFloat, rotation: Double) -> some View {
        Ellipse()
            .stroke(.white.opacity(0.82), lineWidth: 1.6)
            .frame(width: width, height: height)
            .rotationEffect(.degrees(rotation))
    }
}


/// 将横向展开手势直接挂到页面 UIScrollView，避免被卡片和 SwiftUI 滚动手势抢走。
struct FollowingPageSwipeObserver: UIViewRepresentable {
    let enabled: Bool
    let onMove: (CGFloat) -> Void
    let onEnd: (CGFloat?) -> Void

    func makeUIView(context: Context) -> ObserverView { ObserverView() }
    func updateUIView(_ view: ObserverView, context: Context) {
        view.enabled = enabled
        view.onMove = onMove
        view.onEnd = onEnd
        view.attach()
    }
    static func dismantleUIView(_ view: ObserverView, coordinator: ()) { view.detach() }

    @MainActor
    final class ObserverView: UIView, UIGestureRecognizerDelegate {
        var enabled = true
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
            return enabled && velocity.x > 0 && abs(velocity.x) > abs(velocity.y) * 1.3
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            other === scroll?.panGestureRecognizer
        }

        @objc private func panned(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began, .changed:
                onMove?(gesture.translation(in: window).x)
            case .ended:
                onMove?(gesture.translation(in: window).x)
                onEnd?(gesture.velocity(in: window).x)
            case .cancelled, .failed:
                onEnd?(nil)
            default:
                break
            }
        }
    }
}
