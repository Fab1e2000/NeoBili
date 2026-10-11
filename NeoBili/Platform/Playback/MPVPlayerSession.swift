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
        didSet {
            guard onEvent != nil else { viewController.onEvent = nil; return }
            viewController.onEvent = { [weak self] event in
                guard let self else { return }
                switch event {
                case .playing(let playing):
                    if playing { refreshAudioFocusIfNeeded() }
                    else { audioSession.release(audioOwner) }
                case .ended, .error:
                    releaseAudioFocus()
                default: break
                }
                onEvent?(event)
            }
        }
    }

    private(set) var playbackRate: Double = 1
    private var isStopped = false
    private let activatesAudio: Bool
    private let audioSession: PlaybackAudioSession
    private let audioOwner = UUID()
    private var requestsAudio = false

    init(configuration: VideoPlaybackConfiguration, audioSession: PlaybackAudioSession = .shared) {
        activatesAudio = !configuration.silentPreview
        self.audioSession = audioSession
        viewController = MPVMetalViewController(configuration: configuration)
    }

    deinit {
        MainActor.assumeIsolated {
            let audioSession = audioSession, owner = audioOwner
            viewController.stop { audioSession.release(owner) }
        }
    }

    func open(source: PlaybackSource, startTime: TimeInterval = 0) async throws {
        guard !isStopped else { return }
        requestAudioFocus()
        // mpv 只有在 `viewDidLoad` 跑过之后才存在（`engine.start` 在那里调用）。
        // SwiftUI 什么时候真正把 viewController 挂进窗口是不确定的——如果
        // playURL 命中缓存、`load()` 里的 await 几乎立刻返回，这里可能跑在
        // SwiftUI 挂载之前。主动强制加载一次，不能指望调用方替我们做这件事。
        viewController.loadViewIfNeeded()
        viewController.open(source: source, startTime: startTime)
        viewController.setPlaybackRate(playbackRate)
    }

    func setPlaybackRate(_ rate: Double) {
        guard !isStopped, PlaybackSpeed.options.contains(rate) else { return }
        playbackRate = rate
        if viewController.isViewLoaded { viewController.setPlaybackRate(rate) }
    }

    func play() {
        guard !isStopped else { return }
        requestAudioFocus()
        viewController.play()
    }

    func pause() {
        viewController.pause()
        releaseAudioFocus()
    }

    /// 退出手势的提交帧上异步暂停：UIKit 的 zoom 退出动画正要开始，这里
    /// 不能让主线程同步等内核锁。
    func pauseAsync() {
        guard !isStopped else { return }
        requestsAudio = false
        viewController.pauseAsync { [weak self] in
            guard let self, !requestsAudio else { return }
            audioSession.release(audioOwner)
        }
    }

    func seek(to seconds: TimeInterval) async {
        viewController.seek(to: max(seconds, 0))
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        requestsAudio = false
        let audioSession = audioSession, owner = audioOwner
        viewController.stop { audioSession.release(owner) }
    }

    func refreshAudioFocusIfNeeded() {
        if requestsAudio, !isStopped { audioSession.acquire(audioOwner) }
    }

    private func requestAudioFocus() {
        guard activatesAudio else { return }
        requestsAudio = true
        audioSession.acquire(audioOwner)
    }

    private func releaseAudioFocus() {
        requestsAudio = false
        audioSession.release(audioOwner)
    }
}
