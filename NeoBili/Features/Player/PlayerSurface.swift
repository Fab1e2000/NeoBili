import SwiftUI
import UIKit

/// 承载视频像素的渲染层，播放控制仍由 SwiftUI 自己绘制。
/// session 是 PlayerViewModel 持有的稳定对象，横竖屏切换时复用同一个
/// UIViewController，不会因 SwiftUI 重新布局而重建播放内核。
struct PlayerSurface: UIViewControllerRepresentable {
    let session: MPVPlayerSession

    func makeUIViewController(context: Context) -> PlayerSurfaceContainerController {
        let container = PlayerSurfaceContainerController(content: session.viewController)
        return container
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

    deinit {
        // 容器被销毁时，渲染控制器如果还挂在它下面，就等于离开了视图层级。
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.clipsToBounds = true
        if let content { attach(content) }
    }

    /// 真正显示出来的容器要把渲染层要回来。
    ///
    /// SwiftUI 有时会为同一个 session 建**两个** `PlayerSurface` 容器（重新
    /// present 视频页时实测就会），后建的那个会把渲染层从先建的那个手里抢走，
    /// 而留在屏幕上的往往是先建的那个——于是渲染层挂在一个没进窗口的容器下面，
    /// 声音照放，画面全黑。只有真正上屏的容器才会收到出现和布局回调，所以在
    /// 这两处认领一次，屏幕上的那个一定拿得回来。
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reclaimContentIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        reclaimContentIfNeeded()
    }

    private func reclaimContentIfNeeded() {
        guard let content, content.parent !== self else { return }
        attach(content)
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

        // 不要从一个正显示在屏幕上的容器手里抢渲染层。
        // 抢走之后画面就没了，而抢的这一个自己还没上屏（多半根本不会上屏）。
        if let holder = content.parent,
           holder.viewIfLoaded?.window != nil,
           viewIfLoaded?.window == nil {
            return
        }

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
