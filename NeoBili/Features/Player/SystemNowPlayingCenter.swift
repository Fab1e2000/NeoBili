import MediaPlayer
import UIKit

struct SystemMediaMetadata: Equatable, Sendable {
    let identifier: String
    let title: String
    let artist: String
    let artworkURL: URL?
}

/// 把 mpv 的播放状态桥接到锁屏、控制中心、耳机和车载系统。
///
/// `MPNowPlayingInfoCenter` 和 `MPRemoteCommandCenter` 都是进程级单例，因此这里
/// 用 sessionID 拒绝旧播放器迟到的事件，防止切换视频时旧页面清掉新媒体卡片。
@MainActor
final class SystemNowPlayingCenter {
    static let shared = SystemNowPlayingCenter()

    private let infoCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()
    private var commandTargets: [Any] = []
    private var activeSessionID: UUID?
    private var metadata: SystemMediaMetadata?
    private var duration: TimeInterval = 0
    private var elapsed: TimeInterval = 0
    private var playbackRate: Float = 0
    private var lastPublishedSecond = -1
    private var artwork: MPMediaItemArtwork?
    private var artworkTask: Task<Void, Never>?

    private var playHandler: (() -> Void)?
    private var pauseHandler: (() -> Void)?
    private var toggleHandler: (() -> Void)?
    private var seekHandler: ((TimeInterval) -> Void)?

    private init() {
        setCommandsEnabled(false)

        commandTargets.append(commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playHandler?() }
            return .success
        })
        commandTargets.append(commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pauseHandler?() }
            return .success
        })
        commandTargets.append(commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggleHandler?() }
            return .success
        })
        commandTargets.append(commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let position = event.positionTime
            Task { @MainActor in self?.seekHandler?(position) }
            return .success
        })
    }

    func activate(
        sessionID: UUID,
        metadata newMetadata: SystemMediaMetadata,
        onPlay: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onToggle: @escaping () -> Void,
        onSeek: @escaping (TimeInterval) -> Void
    ) {
        let isNewSession = activeSessionID != sessionID
        let artworkChanged = metadata?.artworkURL != newMetadata.artworkURL
        activeSessionID = sessionID
        metadata = newMetadata
        playHandler = onPlay
        pauseHandler = onPause
        toggleHandler = onToggle
        seekHandler = onSeek

        if isNewSession {
            duration = 0
            elapsed = 0
            playbackRate = 0
            lastPublishedSecond = -1
            infoCenter.playbackState = .paused
        }
        setCommandsEnabled(true)
        // 纯 SwiftUI 生命周期里没有 viewController 做第一响应者，必须显式
        // 打开远程控制事件，系统才会把本 App 登记为「正在播放」的媒体应用
        // （灵动岛 / 锁屏 / 控制中心的卡片都挂在这个登记上）。
        UIApplication.shared.beginReceivingRemoteControlEvents()

        if isNewSession || artworkChanged {
            artwork = nil
            loadArtwork(from: newMetadata.artworkURL, sessionID: sessionID)
        }
        publish()
    }

    func updateDuration(_ value: TimeInterval, sessionID: UUID) {
        guard activeSessionID == sessionID, value.isFinite, value > 0 else { return }
        duration = value
        publish()
    }

    func updateElapsed(_ value: TimeInterval, sessionID: UUID, force: Bool = false) {
        guard activeSessionID == sessionID, value.isFinite else { return }
        elapsed = max(value, 0)
        let second = Int(elapsed.rounded(.down))
        guard force || second != lastPublishedSecond else { return }
        lastPublishedSecond = second
        publish()
    }

    func updatePlaybackState(isPlaying: Bool, sessionID: UUID) {
        guard activeSessionID == sessionID else { return }
        playbackRate = isPlaying ? 1 : 0
        infoCenter.playbackState = isPlaying ? .playing : .paused
        publish()
    }

    func deactivate(sessionID: UUID) {
        guard activeSessionID == sessionID else { return }
        artworkTask?.cancel()
        artworkTask = nil
        activeSessionID = nil
        metadata = nil
        artwork = nil
        playHandler = nil
        pauseHandler = nil
        toggleHandler = nil
        seekHandler = nil
        setCommandsEnabled(false)
        UIApplication.shared.endReceivingRemoteControlEvents()
        infoCenter.playbackState = .stopped
        infoCenter.nowPlayingInfo = nil
    }

    static func makeInfo(
        metadata: SystemMediaMetadata,
        duration: TimeInterval,
        elapsed: TimeInterval,
        playbackRate: Float
    ) -> [String: Any] {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: metadata.title,
            MPNowPlayingInfoPropertyExternalContentIdentifier: metadata.identifier,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(elapsed, 0),
            MPNowPlayingInfoPropertyPlaybackRate: playbackRate,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        if !metadata.artist.isEmpty {
            info[MPMediaItemPropertyArtist] = metadata.artist
        }
        if duration.isFinite, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        return info
    }

    private func publish() {
        guard let metadata else { return }
        var info = Self.makeInfo(
            metadata: metadata,
            duration: duration,
            elapsed: elapsed,
            playbackRate: playbackRate
        )
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        infoCenter.nowPlayingInfo = info
    }

    private func setCommandsEnabled(_ enabled: Bool) {
        commandCenter.playCommand.isEnabled = enabled
        commandCenter.pauseCommand.isEnabled = enabled
        commandCenter.togglePlayPauseCommand.isEnabled = enabled
        commandCenter.changePlaybackPositionCommand.isEnabled = enabled
    }

    private func loadArtwork(from url: URL?, sessionID: UUID) {
        artworkTask?.cancel()
        guard let url else {
            artworkTask = nil
            return
        }
        artworkTask = Task { [weak self] in
            var request = URLRequest(url: url)
            request.timeoutInterval = 8
            request.setValue(BiliHeaders.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(BiliHeaders.referer, forHTTPHeaderField: "Referer")
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  !Task.isCancelled,
                  let image = UIImage(data: data)
            else { return }
            let loadedArtwork = Self.makeArtwork(image)
            guard let self, self.activeSessionID == sessionID else { return }
            self.artwork = loadedArtwork
            self.publish()
        }
    }

    /// 在 MainActor 上下文里直接创建 `MPMediaItemArtwork` 会闪退：Swift 6 把
    /// 那里创建的 requestHandler 闭包推断成 MainActor 隔离，而系统推送锁屏
    /// 信息时是在自己的后台队列上调它序列化封面（`jpegDataWithSize:`），动态
    /// 隔离断言当场失败（`_dispatch_assert_queue_fail`）——和 mpv 回调线程那次
    /// 是同一类问题。放进 nonisolated 上下文创建，handler 不带任何隔离，任何
    /// 线程调用都只是返回捕获的这张图。
    private nonisolated static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
