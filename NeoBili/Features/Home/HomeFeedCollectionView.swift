import UIKit

/// 标签栏「下滑收起」要知道页面的主滚动视图。推荐页外面没有导航栈替它登记，
/// 放进窗口时由列表自己登记给所在的视图控制器。
final class HomeFeedCollectionView: UICollectionView {
    var onWindowChanged: (() -> Void)?
    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChanged?()
        guard window != nil else { return }
        var responder: UIResponder? = next
        while let current = responder {
            if let controller = current as? UIViewController {
                if controller.contentScrollView(for: .bottom) !== self {
                    controller.setContentScrollView(self)
                }
                return
            }
            responder = current.next
        }
    }
}

