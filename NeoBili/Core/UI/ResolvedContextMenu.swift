#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI
import UIKit

/// 多选圆圈在卡面外独立响应，预览和按下高亮都沿着视频卡本身。
struct LibraryVideoCardButton<ID: Hashable, Label: View>: View {
    let id: ID
    let registry: ResolvedMenuRegistry<ID>
    let isSelecting: Bool
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        HStack(spacing: 0) {
            if isSelecting {
                Button(action: action) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.app(.title2))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .frame(maxHeight: .infinity)
                        .padding(.trailing, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }

            Button(action: action, label: label)
                .buttonStyle(CardPressStyle(cornerRadius: VideoListCardLayout.cardCornerRadius))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .background { ResolvedMenuMarker(id: id, registry: registry) }
        }
    }
}

@MainActor
final class ResolvedMenuRegistry<ID: Hashable> {
    private var markers: [ObjectIdentifier: ResolvedMenuMarkerView<ID>] = [:]
    var menu: (ID) -> UIMenu = { _ in UIMenu() }

    func action(
        _ title: String.LocalizationValue, systemImage: String, destructive: Bool = false, enabled: Bool = true,
        id: ID, perform: @escaping (ID) -> Void
    ) -> UIAction {
        var attributes: UIMenuElement.Attributes = destructive ? .destructive : []
        if !enabled { attributes.insert(.disabled) }
        return UIAction(title: String(localized: title), image: UIImage(systemName: systemImage), attributes: attributes) { _ in
            perform(id)
        }
    }

    func track(_ marker: ResolvedMenuMarkerView<ID>) { markers[ObjectIdentifier(marker)] = marker }
    fileprivate func untrack(_ marker: ResolvedMenuMarkerView<ID>) { markers.removeValue(forKey: ObjectIdentifier(marker)) }

    func marker(at point: CGPoint, in scroll: UIView) -> ResolvedMenuMarkerView<ID>? {
        guard scroll.bounds.contains(point) else { return nil }
        return markers.values.first { marker in
            guard marker.window != nil, marker.isDescendant(of: scroll) else { return false }
            let local = marker.convert(point, from: scroll)
            return marker.bounds.contains(local) && marker.cardPath.contains(local)
        }
    }

    fileprivate func marker(id: ID, in scroll: UIView) -> ResolvedMenuMarkerView<ID>? {
        markers.values.first { $0.id == id && $0.window != nil && $0.isDescendant(of: scroll) }
    }
}

final class ResolvedMenuMarkerView<ID: Hashable>: UIView {
    var id: ID?
    weak var registry: ResolvedMenuRegistry<ID>?

    var cardPath: UIBezierPath {
        let shape = RoundedRectangle(cornerRadius: VideoListCardLayout.cardCornerRadius, style: .continuous)
        return UIBezierPath(cgPath: shape.path(in: bounds).cgPath)
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
            // 快速切换卡片时，UIKit 可能仍传来旧菜单的位置。只读取这次仍按着的手指。
            let point = press.numberOfTouches > 0 && press.view?.window === window
                ? press.location(in: scroll) : location
            guard let id = registry.marker(at: point, in: scroll)?.id else { return nil }
            let token = ResolvedMenuToken(id: id)
            return UIContextMenuConfiguration(identifier: token, previewProvider: nil) { [registry] _ in
                registry.menu(id)
            }
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
            preview(for: configuration, in: interaction.view)
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
            preview(for: configuration, in: interaction.view)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }

        private func preview(for configuration: UIContextMenuConfiguration, in scroll: UIView?) -> UITargetedPreview? {
            guard let scroll, scroll.window != nil, let token = configuration.identifier as? ResolvedMenuToken<ID>,
                  let marker = registry.marker(id: token.id, in: scroll) else { return nil }
            let rect = marker.convert(marker.bounds, to: scroll)
            let target = UIPreviewTarget(container: scroll, center: CGPoint(x: rect.midX, y: rect.midY))
            if let preview = token.preview {
                return preview.retargetedPreview(with: target)
            }
            // SwiftUI 卡面和透明标记可能不在同一层。只截取标记覆盖的内容，卡间距和勾选框留在原位。
            guard let snapshot = scroll.resizableSnapshotView(from: rect, afterScreenUpdates: false, withCapInsets: .zero) else { return nil }
            let parameters = UIPreviewParameters()
            parameters.backgroundColor = .secondarySystemGroupedBackground
            parameters.visiblePath = marker.cardPath
            let preview = UITargetedPreview(view: snapshot, parameters: parameters, target: target)
            token.preview = preview
            return preview
        }
    }
}

private final class ResolvedMenuToken<ID: Hashable>: NSObject, NSCopying {
    let id: ID
    @MainActor var preview: UITargetedPreview?
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
