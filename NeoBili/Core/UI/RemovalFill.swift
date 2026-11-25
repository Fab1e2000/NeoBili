import NeoBiliDomain
import SwiftUI
import UIKit

/// 从列表里删掉内容后，被删的那一项缩小淡出，其余项保持原来的先后顺序移过来补位。
/// 推荐页的网格、收藏夹列表和评论集合视图走同一段 UIKit 弹簧；SwiftUI 列表用对应的弹簧。
enum RemovalFill {
    static let duration: TimeInterval = 0.3
    static let damping: CGFloat = 0.88
    static let scale: CGFloat = 0.85

    /// 接近 UIKit `damping = 0.88` 的轻微回弹。
    static var animation: Animation { .spring(duration: duration, bounce: 0.2) }

    /// 只去掉了若干项，留下来的项顺序没变。空列表不算，避免首次出现被当成删除。
    static func isRemovalOnly<ID: Hashable>(_ previous: [ID], _ current: [ID]) -> Bool {
        guard !previous.isEmpty, current.count < previous.count else { return false }
        let remaining = Set(current)
        return previous.filter(remaining.contains) == current
    }

    /// 新项插进原有序列，原有项的顺序没变。末尾追加也算，收藏夹没有分页，撤销最后一项要用它。
    static func isOrderPreservingInsertion<ID: Hashable>(_ previous: [ID], _ current: [ID]) -> Bool {
        guard !previous.isEmpty, current.count > previous.count else { return false }
        let existing = Set(previous)
        return current.filter(existing.contains) == previous
    }

    /// 插在中间，不是纯往末尾追加。历史、收藏和稍后再看的翻页是末尾追加，不该补位。
    static func isInlineInsertion<ID: Hashable>(_ previous: [ID], _ current: [ID]) -> Bool {
        isOrderPreservingInsertion(previous, current) && !current.starts(with: previous)
    }

    static func shouldAnimate<ID: Hashable>(from previous: [ID], to current: [ID], scope: RemovalFillScope) -> Bool {
        if isRemovalOnly(previous, current) { return true }
        switch scope {
        case .removal:
            return false
        case .removalAndInlineRestore:
            return isInlineInsertion(previous, current)
        }
    }

    @MainActor
    static func perform(_ changes: () -> Void, completion: ((Bool) -> Void)? = nil) {
        UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: damping,
                       initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState],
                       animations: changes, completion: completion)
    }
}

enum RemovalFillScope {
    /// 按原顺序删除时动画。刷新、翻页和末尾追加保持瞬时。
    case removal
    /// 删除，以及把条目插回中间。末尾追加仍视为翻页。
    case removalAndInlineRestore
}

extension EnvironmentValues {
    /// 集合视图会复用评论格。格子里不要自己记上一帧的身份，避免复用后误判成删除。
    @Entry var removalFillTracksIdentity = true
}

extension View {
    /// 容器监听 `ids`。只有这次变化符合 `scope` 时，同一轮里的行删除和位移才被动画。
    func removalFill<ID: Hashable>(ids: [ID], enabled: Bool, scope: RemovalFillScope = .removal) -> some View {
        modifier(RemovalFillModifier(ids: ids, enabled: enabled, scope: scope))
    }

    func removalFillTransition() -> some View {
        transition(.scale(scale: RemovalFill.scale).combined(with: .opacity))
    }
}

private struct RemovalFillModifier<ID: Hashable>: ViewModifier {
    var ids: [ID]
    var enabled: Bool
    var scope: RemovalFillScope
    @State private var previous: [ID] = []

    func body(content: Content) -> some View {
        let animation: Animation? = enabled && RemovalFill.shouldAnimate(from: previous, to: ids, scope: scope)
            ? RemovalFill.animation : nil
        content
            .animation(animation, value: ids)
            .onChange(of: ids, initial: true) { _, new in previous = new }
    }
}

/// 集合视图补位时，被删掉的格子缩小淡出；移到新位置的格子只平移。
class RemovalFillLayout: UICollectionViewCompositionalLayout {
    var shrinksDeletedItems = false
    private var deletedIndexPaths: Set<IndexPath> = []

    convenience init(list configuration: UICollectionLayoutListConfiguration) {
        self.init { _, environment in
            NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
        }
    }

    override func prepare(forCollectionViewUpdates updateItems: [UICollectionViewUpdateItem]) {
        super.prepare(forCollectionViewUpdates: updateItems)
        deletedIndexPaths = Set(updateItems.filter { $0.updateAction == .delete }.compactMap(\.indexPathBeforeUpdate))
    }

    override func finalizeCollectionViewUpdates() {
        super.finalizeCollectionViewUpdates()
        deletedIndexPaths = []
    }

    override func finalLayoutAttributesForDisappearingItem(at itemIndexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        let attributes = super.finalLayoutAttributesForDisappearingItem(at: itemIndexPath)
        guard shrinksDeletedItems, deletedIndexPaths.contains(itemIndexPath),
              let shrunk = attributes?.copy() as? UICollectionViewLayoutAttributes else { return attributes }
        shrunk.alpha = 0
        shrunk.transform = CGAffineTransform(scaleX: RemovalFill.scale, y: RemovalFill.scale)
        return shrunk
    }
}
