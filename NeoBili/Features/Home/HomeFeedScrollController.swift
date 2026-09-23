import UIKit

/// 推荐页列表的滚动控制，给标签栏「回顶 / 刷新」和刷新后回顶使用。
@MainActor
final class HomeFeedScrollController {
    weak var collectionView: UICollectionView?

    var isAwayFromTop: Bool {
        guard let collectionView else { return false }
        return collectionView.contentOffset.y + collectionView.adjustedContentInset.top > 1
    }

    func scrollToTop(animated: Bool) {
        guard let collectionView else { return }
        collectionView.setContentOffset(
            CGPoint(x: collectionView.contentOffset.x, y: -collectionView.adjustedContentInset.top),
            animated: animated
        )
    }
}
