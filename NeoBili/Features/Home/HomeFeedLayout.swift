import UIKit

/// 首页的网格布局。只在移除卡片的补位动画里，让被删掉的那张缩小淡出；
/// 移动到新位置的卡片照常平移，不受影响。
final class HomeFeedLayout: UICollectionViewCompositionalLayout {
    var shrinksDeletedItems = false
    private var deletedIndexPaths: Set<IndexPath> = []

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
        shrunk.transform = CGAffineTransform(scaleX: 0.85, y: 0.85)
        return shrunk
    }
}
