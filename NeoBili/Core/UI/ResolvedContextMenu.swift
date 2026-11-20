#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI
import UIKit

/// 长按菜单只决定命令。卡片由手指落点决定：系统退场时会用上一张卡的位置再要一次菜单。
enum ResolvedContextMenu {
    static func finger<ID: Hashable>(_ id: ID?, at date: Date, now: Date, maxAge: TimeInterval = 8) -> ID? {
        guard let id, now.timeIntervalSince(date) < maxAge else { return nil }
        return id
    }

    /// 重叠时取面积最小的矩形，避免外层容器盖住卡片。
    static func container<ID: Hashable>(at point: CGPoint, rects: [ID: CGRect]) -> ID? {
        rects.filter { $0.value.contains(point) }
            .min { $0.value.width * $0.value.height < $1.value.width * $1.value.height }?.key
    }
}

@MainActor
final class ResolvedMenuRegistry<ID: Hashable> {
    fileprivate var markers: [ObjectIdentifier: ResolvedMenuMarkerView<ID>] = [:]
    fileprivate var layoutFrames: [ID: CGRect] = [:]
    fileprivate var fingerID: ID?
    fileprivate var fingerAt = Date.distantPast
    var menu: (ID) -> UIMenu = { _ in UIMenu() }

    func setLayoutFrame(_ id: ID, _ rect: CGRect) { layoutFrames[id] = rect }
    func clearLayoutFrame(_ id: ID) { layoutFrames[id] = nil }

    func target(fallback: ID, now: Date = Date()) -> ID { finger(now: now) ?? fallback }

    func finger(within seconds: TimeInterval = 8, now: Date = Date()) -> ID? {
        ResolvedContextMenu.finger(fingerID, at: fingerAt, now: now, maxAge: seconds)
    }

    func action(
        _ title: String.LocalizationValue, systemImage: String, destructive: Bool = false, enabled: Bool = true,
        fallback: ID, perform: @escaping (ID) -> Void
    ) -> UIAction {
        var attributes: UIMenuElement.Attributes = destructive ? .destructive : []
        if !enabled { attributes.insert(.disabled) }
        return UIAction(title: String(localized: title), image: UIImage(systemName: systemImage), attributes: attributes) { [weak self] _ in
            guard let self else { return }
            perform(self.target(fallback: fallback))
        }
    }

    fileprivate func track(_ marker: ResolvedMenuMarkerView<ID>) { markers[ObjectIdentifier(marker)] = marker }
    fileprivate func untrack(_ marker: ResolvedMenuMarkerView<ID>) { markers.removeValue(forKey: ObjectIdentifier(marker)) }

    fileprivate func arm(at point: CGPoint, in window: UIWindow) {
        guard let id = id(at: point, in: window) else { return }
        fingerID = id
        fingerAt = Date()
    }

    /// SwiftUI 全局坐标和窗口坐标不一定相同，两种都试。
    fileprivate func id(at point: CGPoint, in window: UIWindow) -> ID? {
        let screen = window.convert(point, to: nil)
        if let id = ResolvedContextMenu.container(at: screen, rects: layoutFrames) { return id }
        guard screen != point else { return nil }
        return ResolvedContextMenu.container(at: point, rects: layoutFrames)
    }

    fileprivate func marker(id: ID) -> ResolvedMenuMarkerView<ID>? {
        markers.values.first { $0.id == id && $0.window != nil }
    }
}

final class ResolvedMenuMarkerView<ID: Hashable>: UIView {
    var id: ID?
    weak var registry: ResolvedMenuRegistry<ID>?

    /// 标记本身是透明背景，预览要落到包住卡片内容的那一层。
    func previewContainer() -> UIView {
        var best: UIView = self
        var node: UIView = self
        while let parent = node.superview {
            guard parent.bounds.height <= bounds.height + 24, parent.bounds.width <= bounds.width + 8,
                  parent.bounds.height + 1 >= bounds.height else { break }
            best = parent
            node = parent
        }
        return best
    }
}

struct ResolvedMenuMarker<ID: Hashable>: UIViewRepresentable {
    var id: ID
    var registry: ResolvedMenuRegistry<ID>

    func makeUIView(context: Context) -> ResolvedMenuMarkerView<ID> {
        let view = ResolvedMenuMarkerView<ID>()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ uiView: ResolvedMenuMarkerView<ID>, context: Context) {
        uiView.id = id
        uiView.registry = registry
        registry.track(uiView)
    }

    static func dismantleUIView(_ uiView: ResolvedMenuMarkerView<ID>, coordinator: ()) {
        uiView.registry?.untrack(uiView)
        uiView.registry = nil
    }
}

struct ResolvedMenuInstaller<ID: Hashable>: UIViewRepresentable {
    var registry: ResolvedMenuRegistry<ID>
    var menu: (ID) -> UIMenu

    func makeCoordinator() -> Coordinator { Coordinator(registry: registry) }

    func makeUIView(context: Context) -> Host {
        let view = Host()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: Host, context: Context) {
        registry.menu = menu
        context.coordinator.registry = registry
        uiView.attachIfNeeded()
    }

    static func dismantleUIView(_ uiView: Host, coordinator: Coordinator) {
        coordinator.detach()
        uiView.coordinator = nil
    }

    final class Host: UIView {
        weak var coordinator: Coordinator?
        override func didMoveToWindow() { super.didMoveToWindow(); attachIfNeeded() }
        override func layoutSubviews() { super.layoutSubviews(); attachIfNeeded() }
        func attachIfNeeded() { coordinator?.attach(from: self) }
    }

    @MainActor
    final class Coordinator: NSObject, UIContextMenuInteractionDelegate, UIGestureRecognizerDelegate {
        var registry: ResolvedMenuRegistry<ID>
        private var interaction: UIContextMenuInteraction!
        private let press = StationaryLongPress()
        private weak var observedWindow: UIWindow?

        init(registry: ResolvedMenuRegistry<ID>) {
            self.registry = registry
            super.init()
            interaction = UIContextMenuInteraction(delegate: self)
            press.minimumPressDuration = 0.25
            press.cancelsTouchesInView = false
            press.delaysTouchesBegan = false
            press.delaysTouchesEnded = false
            press.delegate = self
            press.addTarget(self, action: #selector(longPressed(_:)))
        }

        @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let window = gesture.view as? UIWindow ?? gesture.view?.window else { return }
            registry.arm(at: gesture.location(in: window), in: window)
        }

        func attach(from view: UIView) {
            guard let scroll = view.enclosingScrollView() else { return }
            if interaction.view !== scroll {
                interaction.view?.removeInteraction(interaction)
                scroll.addInteraction(interaction)
            }
            guard let window = view.window, observedWindow !== window else { return }
            press.view?.removeGestureRecognizer(press)
            window.addGestureRecognizer(press)
            observedWindow = window
        }

        func detach() {
            interaction.view?.removeInteraction(interaction)
            press.view?.removeGestureRecognizer(press)
            observedWindow = nil
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
            guard let scroll = interaction.view, let window = scroll.window else { return nil }
            let point = (press.state == .began || press.state == .changed)
                ? press.location(in: window) : scroll.convert(location, to: window)
            guard let id = registry.id(at: point, in: window) ?? registry.finger() else { return nil }
            let token = ResolvedMenuToken(id: id)
            return UIContextMenuConfiguration(identifier: token, previewProvider: nil) { [registry] _ in
                registry.menu(id)
            }
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
            preview(for: configuration)
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
            preview(for: configuration)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

        private func preview(for configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
            guard let token = configuration.identifier as? ResolvedMenuToken<ID>,
                  let marker = registry.marker(id: token.id), marker.window != nil else { return nil }
            let view = marker.previewContainer()
            let parameters = UIPreviewParameters()
            parameters.backgroundColor = .clear
            parameters.visiblePath = UIBezierPath(roundedRect: view.bounds, cornerRadius: 10)
            return UITargetedPreview(view: view, parameters: parameters)
        }
    }
}

private final class ResolvedMenuToken<ID: Hashable>: NSObject, NSCopying {
    let id: ID
    init(id: ID) { self.id = id }
    func copy(with zone: NSZone? = nil) -> Any { self }
}

/// 系统预览手势不能取消这次长按，否则第二下落点登记不上。
private final class StationaryLongPress: UILongPressGestureRecognizer {
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}

private extension UIView {
    func enclosingScrollView() -> UIScrollView? {
        sequence(first: superview, next: { $0?.superview }).compactMap { $0 as? UIScrollView }.first
    }
}
