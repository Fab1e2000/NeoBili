import SwiftUI
import UIKit

struct FollowingAvatarScroll: UIViewRepresentable {
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
    let onOpenLive: (FollowedUp) -> Void
    let onContextMenuChange: (Bool) -> Void
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
        controller.onOpenLive = onOpenLive
        controller.onContextMenuChange = onContextMenuChange
        controller.onAlignment = onAlignment
        controller.configure(items: items, initialID: initialID, side: side, rowHeight: rowHeight, expanded: isExpanded, interactiveProgress: interactiveProgress)
    }
    static func dismantleUIView(_ view: FollowingAvatarGlassView, coordinator: FollowingAvatarScrollController) {
        view.collection.onLayout = nil
        if coordinator.collection === view.collection { coordinator.detach() }
    }
}

/// 头像必须放进玻璃的 contentView，避免跨 SwiftUI/UIKit 合成时被当作背景再次折射。
final class FollowingAvatarGlassView: UIView {
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
        // presentation() 在 CAShapeLayer 上返回的就是 CAShapeLayer?，无需再向下转型。
        guard super.point(inside: point, with: event),
              let visible = outline.presentation()?.path ?? outline.path else { return false }
        return visible.contains(point)
    }

    func updateExtent(_ occupied: ClosedRange<CGFloat>, progress: CGFloat, animated: Bool, interactive: Bool) {
        guard bounds.height > 0 else { return }
        // 收起时玻璃整块退到屏幕外，边缘不留把手；展开时从边缘滑入。
        let collapsed = CGRect(x: side == .left ? -60 : bounds.width, y: bounds.midY - 30, width: 60, height: 60)
        let target = CGRect(x: 0, y: occupied.lowerBound, width: bounds.width, height: occupied.upperBound - occupied.lowerBound)
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * progress }
        let rect = CGRect(x: mix(collapsed.minX, target.minX), y: mix(collapsed.minY, target.minY),
                          width: mix(collapsed.width, target.width), height: mix(collapsed.height, target.height))
        let shape = FollowingSidebarShape(side: side, focusY: bounds.midY - rect.minY,
                                          spineWidth: mix(60, 56), bulge: 32 * progress)
        let path = shape.path(in: rect).cgPath
        let old = outline.presentation()?.path ?? outline.path
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

final class FollowingAvatarCollectionView: UICollectionView {
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
        accessibilityLabel = item.title + (item.up?.liveRoomID != nil ? "，正在直播" : "")
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

    func contextMenuPreview() -> UITargetedPreview {
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        let outline = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: avatarSize, height: avatarSize))
        if item.up?.liveRoomID != nil {
            outline.append(UIBezierPath(roundedRect: CGRect(x: avatarSize * 0.15, y: avatarSize * 0.82,
                                                           width: avatarSize * 0.7, height: avatarSize * 0.28),
                                        cornerRadius: avatarSize * 0.14))
        }
        parameters.visiblePath = outline
        // Lift only the circular avatar and its badge, never the rectangular collection cell.
        return UITargetedPreview(view: host.view, parameters: parameters)
    }

    private func positionAvatar() {
        let expandedX = side == .left ? 28 + 20 * weight : bounds.width - 28 - 20 * weight
        let collapsedX: CGFloat = side == .left ? 0 : bounds.width
        let x = collapsedX + (expandedX - collapsedX) * expansionProgress
        let badgeHeight = item.up?.liveRoomID != nil ? avatarSize / 10 : 0
        let scale = 1 + 0.5 * weight
        host.view.bounds = CGRect(x: 0, y: 0, width: avatarSize, height: avatarSize + badgeHeight)
        host.view.center = CGPoint(x: x, y: bounds.height / 2 + badgeHeight * scale / 2)
        host.view.transform = CGAffineTransform(scaleX: scale, y: scale)
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
    private var isContextMenuPresented = false
    private var pendingMenuAction: (() -> Void)?
    var onFocus: (FollowingSelection.ID) -> Void = { _ in }
    var onSettled: (FollowingSelection.ID) -> Void = { _ in }
    var onOpenUp: (FollowedUp) -> Void = { _ in }
    var onOpenLive: (FollowedUp) -> Void = { _ in }
    var onContextMenuChange: (Bool) -> Void = { _ in }
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
        pendingMenuAction = nil
        if isContextMenuPresented { onContextMenuChange(false) }
        isContextMenuPresented = false
        collection = nil
        onFocus = { _ in }; onSettled = { _ in }; onAlignment = { _ in }; onOpenUp = { _ in }
        onOpenLive = { _ in }; onContextMenuChange = { _ in }
    }

    fileprivate func configure(items: [FollowingSelection], initialID: FollowingSelection.ID, side: FollowingSidebarSide, rowHeight: CGFloat, expanded: Bool, interactiveProgress: CGFloat?) {
        guard let collection, !isContextMenuPresented else { return }
        let changed = self.items != items
        if changed, self.expanded, self.items.indices.contains(selectedIndex),
           let newIndex = items.firstIndex(where: { $0.id == self.items[selectedIndex].id }),
           newIndex != selectedIndex {
            selectedIndex = newIndex
            hasPosition = false
        }
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
        guard let collection, !isContextMenuPresented, collection.bounds.height > 0, !items.isEmpty else { return }
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
        guard let collection, !isContextMenuPresented, hasPosition, !items.isEmpty else { return }
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
            guard let self, !self.isContextMenuPresented, let collection, self.collection === collection else { return }
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
        guard !isContextMenuPresented else { return }
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
        guard let collection, !isContextMenuPresented, hasPosition else { return }
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
        guard let collection, !isContextMenuPresented else { stop(); return }
        let dt = max(0, link.timestamp - lastTime)
        lastTime = link.timestamp
        let next = FollowingSidebarPhysics.advanceUnbounded(
            .init(progress: collection.contentOffset.y, velocity: velocity),
            toward: target, elapsed: dt, frequency: 18
        )
        let offset = clamped(next.progress)
        velocity = offset == next.progress ? next.velocity : 0
        collection.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
        if abs(target - offset) < 0.3 && abs(velocity) < 3 {
            collection.setContentOffset(CGPoint(x: 0, y: target), animated: false)
            stop()
            if items.indices.contains(selectedIndex) { onSettled(items[selectedIndex].id) }
        }
    }
    func stop() { displayLink?.invalidate(); displayLink = nil }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        stop()
        guard !isContextMenuPresented, items.indices.contains(indexPath.item) else { return }
        let y = CGFloat(indexPath.item) * rowHeight - collectionView.contentInset.top
        collectionView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
        onSettled(items[indexPath.item].id)
    }
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        guard expanded, let index = indexPaths.first?.item,
              items.indices.contains(index), let up = items[index].up else { return nil }
        stop()
        external = false
        return UIContextMenuConfiguration(identifier: NSNumber(value: up.mid), previewProvider: nil) { [weak self] _ in
            self?.contextMenu(for: up)
        }
    }

    func contextMenu(for up: FollowedUp) -> UIMenu {
        var actions: [UIAction] = []
        if up.liveRoomID != nil {
            actions.append(UIAction(title: "进入直播间", image: UIImage(systemName: "dot.radiowaves.left.and.right")) { [weak self] _ in
                self?.afterContextMenu { [weak self] in self?.onOpenLive(up) }
            })
        }
        actions.append(UIAction(title: "查看 UP 主主页", image: UIImage(systemName: "person.crop.circle")) { [weak self] _ in
            self?.afterContextMenu { [weak self] in self?.onOpenUp(up) }
        })
        return UIMenu(children: actions)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfiguration configuration: UIContextMenuConfiguration,
                        highlightPreviewForItemAt indexPath: IndexPath) -> UITargetedPreview? {
        (collectionView.cellForItem(at: indexPath) as? FollowingAvatarCell)?.contextMenuPreview()
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfiguration configuration: UIContextMenuConfiguration,
                        dismissalPreviewForItemAt indexPath: IndexPath) -> UITargetedPreview? {
        (collectionView.cellForItem(at: indexPath) as? FollowingAvatarCell)?.contextMenuPreview()
    }

    func collectionView(_ collectionView: UICollectionView, willDisplayContextMenu configuration: UIContextMenuConfiguration,
                        animator: (any UIContextMenuInteractionAnimating)?) {
        stop()
        external = false
        isContextMenuPresented = true
        collectionView.isScrollEnabled = false
        onContextMenuChange(true)
    }

    func collectionView(_ collectionView: UICollectionView, willEndContextMenuInteraction configuration: UIContextMenuConfiguration,
                        animator: (any UIContextMenuInteractionAnimating)?) {
        let finish = { [weak self, weak collectionView] in
            guard let self, self.collection === collectionView else { return }
            self.isContextMenuPresented = false
            collectionView?.isScrollEnabled = self.expanded
            self.onContextMenuChange(false)
            let action = self.pendingMenuAction
            self.pendingMenuAction = nil
            action?()
        }
        if let animator { animator.addCompletion(finish) } else { finish() }
    }

    private func afterContextMenu(_ action: @escaping () -> Void) {
        // Keep the sidebar in place until UIKit has put its lifted preview back.
        if isContextMenuPresented { pendingMenuAction = action } else { action() }
    }
}
