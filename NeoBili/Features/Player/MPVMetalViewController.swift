import Foundation
import UIKit

/// 只负责承载渲染层和转发通知——真正的 mpv 逻辑全在 `MPVEngine` 里。
/// 这里所有方法都只会从 MainActor 调用（`MPVPlayerSession` 的方法、UIKit
/// 自己的生命周期回调、`NotificationCenter` 的这两个前后台通知本身就在
/// 主线程发出），从没有 mpv 的回调线程直接摸这个类。
final class MPVMetalViewController: UIViewController {
    private(set) var videoOutput = PlayerVideoOutputState()
    private let engine: MPVEngine
    private let metalLayer = MPVMetalLayer()
    private var stableSurfaceSize: CGSize = .zero
    private var displayAspectRatio: Double?

    var onEvent: ((PlayerPlaybackEvent) -> Void)?

    init(configuration: VideoPlaybackConfiguration) {
        engine = MPVEngine(configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        engine.onEvent = { [weak self] event in
            guard let self else { return }
            if case .displayAspectRatio(let ratio) = event {
                displayAspectRatio = ratio
                if isViewLoaded { layoutMetalLayer() }
            }
            // UIKit owns the interactive zoom until completion (including a
            // cancelled gesture). Keep decoding, but avoid rebuilding SwiftUI
            // and injecting text bitmaps into that transition's transaction.
            if case .position = event, transitionCoordinator != nil { return }
            onEvent?(event)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.clipsToBounds = true
        metalLayer.contentsScale = traitCollection.displayScale
        // 始终按设备横屏的完整像素尺寸渲染。内联与全屏只改变 layer 的显示
        // 几何，不改变 Vulkan surface，因此整个方向动画都不需要重建 swapchain。
        if let screen = activeScreen {
            let drawableSize = PlayerSurfaceGeometry.stableDrawableSize(
                for: screen.nativeBounds.size
            )
            metalLayer.drawableSize = drawableSize
            stableSurfaceSize = PlayerSurfaceGeometry.pointSize(
                for: drawableSize,
                displayScale: metalLayer.contentsScale
            )
        }
        metalLayer.bounds = CGRect(origin: .zero, size: stableSurfaceSize)
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = UIColor.black.cgColor
        view.layer.addSublayer(metalLayer)
        layoutMetalLayer()

        engine.start(renderingInto: metalLayer)
        videoOutput.isBackgrounded = UIApplication.shared.applicationState == .background
        engine.setVideoEnabled(videoOutput.isEnabled)

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification, object: nil
        )
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutMetalLayer()
    }

    /// 渲染控制器有没有挂在某个容器下面。脱离父级就等于画面不再显示。
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }

    private func layoutMetalLayer() {
        // The outer UIKit zoom already interpolates geometry. An implicit
        // animation on the Metal sublayer starts a second easing at release.
        CATransaction.begin()
        if transitionCoordinator != nil { CATransaction.setDisableActions(true) }
        defer { CATransaction.commit() }
        guard stableSurfaceSize.width > 0, stableSurfaceSize.height > 0 else {
            metalLayer.frame = view.bounds
            return
        }

        // CAMetalLayer 的 drawable 大于 bounds 时不会按 contentsGravity 缩放，
        // 而是从左上角直接裁切（真机截图里的左侧黑条正来源于此）。让 layer
        // 自己始终保持横屏 bounds，再按其中实际视频区域做居中等比缩放，才能既
        // 保持同一个 swapchain，又让各种画幅完整显示。系统旋转会连续插值这个
        // position/transform，所以全屏切换仍然连贯。
        let scale = PlayerSurfaceGeometry.presentationScale(
            surfaceSize: stableSurfaceSize,
            containerSize: view.bounds.size,
            videoAspectRatio: displayAspectRatio
        )
        metalLayer.bounds = CGRect(origin: .zero, size: stableSurfaceSize)
        metalLayer.position = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        metalLayer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
    }

    private var activeScreen: UIScreen? {
        if let screen = view.window?.windowScene?.screen { return screen }
        return UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen }
            .first
    }

    func open(source: PlaybackSource, startTime: TimeInterval = 0) {
        engine.open(source: source, startTime: startTime)
    }
    func play() { engine.play() }
    func pause() { engine.pause() }
    /// 供退出手势的提交帧调用：不等内核锁，命令排队执行。
    func pauseAsync() { engine.pauseAsync() }
    func seek(to seconds: TimeInterval) { engine.seek(to: seconds) }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        engine.stop()
    }

    deinit {
    }

    func setVideoPresentation(_ presentation: PlayerSurfacePresentation) {
        let previous = videoOutput.isEnabled
        videoOutput.presentation = presentation
        if isViewLoaded, previous != videoOutput.isEnabled {
            engine.setVideoEnabled(videoOutput.isEnabled)
        }
    }

    private func setBackgrounded(_ backgrounded: Bool) {
        let previous = videoOutput.isEnabled
        videoOutput.isBackgrounded = backgrounded
        if previous != videoOutput.isEnabled { engine.setVideoEnabled(videoOutput.isEnabled) }
    }

    @objc private func handleDidEnterBackground() { setBackgrounded(true) }
    @objc private func handleWillEnterForeground() { setBackgrounded(false) }
}
