import Foundation
import UIKit

@MainActor
final class MPVPlayerSession {
    let viewController: MPVMetalViewController
    /// 先切换渲染归属，再切换界面，旧页面的延迟布局不能抢回小窗画面。
    let surfaceOwnership = PlayerSurfaceOwnership()
    var surfacePresentation: PlayerSurfacePresentation {
        get { surfaceOwnership.presentation }
        set {
            surfaceOwnership.presentation = newValue
            viewController.setVideoPresentation(newValue)
        }
    }
    var onEvent: ((PlayerPlaybackEvent) -> Void)? {
        didSet { viewController.onEvent = onEvent }
    }

    private var isStopped = false

    init(configuration: VideoPlaybackConfiguration) {
        PlaybackAudioSession.activateOnce()
        viewController = MPVMetalViewController(configuration: configuration)
    }

    func open(source: PlaybackSource, startTime: TimeInterval = 0) async throws {
        guard !isStopped else { return }
        // mpv 只有在 `viewDidLoad` 跑过之后才存在（`engine.start` 在那里调用）。
        // SwiftUI 什么时候真正把 viewController 挂进窗口是不确定的——如果
        // playURL 命中缓存、`load()` 里的 await 几乎立刻返回，这里可能跑在
        // SwiftUI 挂载之前。主动强制加载一次，不能指望调用方替我们做这件事。
        viewController.loadViewIfNeeded()
        viewController.open(source: source, startTime: startTime)
    }

    func play() {
        guard !isStopped else { return }
        PlaybackAudioSession.activateOnce()
        viewController.play()
    }

    func pause() {
        viewController.pause()
    }

    /// 退出手势的提交帧上异步暂停：UIKit 的 zoom 退出动画正要开始，这里
    /// 不能让主线程同步等内核锁。
    func pauseAsync() {
        guard !isStopped else { return }
        viewController.pauseAsync()
    }

    func seek(to seconds: TimeInterval) async {
        viewController.seek(to: max(seconds, 0))
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        viewController.stop()
    }
}
