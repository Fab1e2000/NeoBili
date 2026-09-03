import SwiftUI
import UIKit

/// 承载视频像素的渲染层，播放控制仍由 SwiftUI 自己绘制。
/// session 是 PlayerViewModel 持有的稳定对象，横竖屏切换时复用同一个
/// UIViewController，不会因 SwiftUI 重新布局而重建播放内核。
struct PlayerSurface: UIViewControllerRepresentable {
    let session: MPVPlayerSession

    func makeUIViewController(context: Context) -> PlayerSurfaceContainerController {
        PlayerSurfaceContainerController(content: session.viewController)
    }

    func updateUIViewController(_ uiViewController: PlayerSurfaceContainerController, context: Context) {
        // session 换了（切分P、切相关视频）时把新的渲染控制器接过来。
        // 播放命令仍旧全部由 session 发出。
        uiViewController.adopt(session.viewController)
    }
}

/// 一层只负责搭台子的容器。
///
/// `makeUIViewController` 之前直接把 `session.viewController` 交给 SwiftUI，
/// 而那是 session 自己长期持有的对象。SwiftUI 认为从 make 拿到的控制器归它
/// 管：视图重建时它会把「新」控制器挂上去，再把旧的那一个从父控制器上摘掉
/// —— 两者是同一个实例，于是渲染层被摘走了。播放内核毫无察觉，声音照放，
/// 画面变成一块黑。中间垫一个每次都新建的容器，SwiftUI 摘掉的就只是容器，
/// 渲染控制器始终跟着 session 活着。
@MainActor
final class PlayerSurfaceContainerController: UIViewController {
    private weak var content: UIViewController?

    init(content: UIViewController) {
        super.init(nibName: nil, bundle: nil)
        self.content = content
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.clipsToBounds = true
        if let content { attach(content) }
    }

    /// 幂等：已经装着这个控制器就什么都不做，否则先从旧的父级上摘干净再接过来。
    func adopt(_ newContent: UIViewController) {
        guard content !== newContent || newContent.parent !== self else {
            content = newContent
            return
        }
        if let content, content !== newContent {
            content.willMove(toParent: nil)
            content.view.removeFromSuperview()
            content.removeFromParent()
        }
        content = newContent
        guard isViewLoaded else { return }
        attach(newContent)
    }

    private func attach(_ content: UIViewController) {
        guard content.parent !== self else { return }
        if content.parent != nil {
            content.willMove(toParent: nil)
            content.view.removeFromSuperview()
            content.removeFromParent()
        }
        addChild(content)
        content.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content.view)
        NSLayoutConstraint.activate([
            content.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.view.topAnchor.constraint(equalTo: view.topAnchor),
            content.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        content.didMove(toParent: self)
    }
}
