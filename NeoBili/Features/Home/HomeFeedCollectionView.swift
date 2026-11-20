import UIKit

/// 把原生列表登记为所在控制器的主滚动视图，供系统导航栏与标签栏响应滚动。
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

