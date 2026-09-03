import Foundation
import SwiftUI

typealias PlaybackURLLoader = @Sendable (String, Int) async throws -> PlayURLData

/// 提前保存视频详情和播放地址，点进卡片时就不必重复等待相同请求。
/// 这里只缓存接口返回的小段文字数据，不会提前下载整段视频。
actor VideoPreparationCache {
    static let shared = VideoPreparationCache()

    private struct PlaybackKey: Hashable, Sendable {
        let bvid: String
        let cid: Int
    }

    private struct CachedValue<Value: Sendable>: Sendable {
        let value: Value
        let savedAt: Date
    }

    private let lifetime: TimeInterval = 5 * 60
    private let maximumEntries = 8
    /// 同时最多预取几个视频。数字越大越占用带宽，会拖慢用户真正点开的那个。
    private let maximumConcurrentPrefetches = 2
    /// 等待队列的上限。超过这个数量说明用户在快速滑动，多余的卡片直接放弃预取。
    private let maximumQueuedPrefetches = 4

    private var details: [String: CachedValue<VideoDetail>] = [:]
    private var playbackURLs: [PlaybackKey: CachedValue<PlayURLData>] = [:]
    private var detailTasks: [String: Task<VideoDetail, Error>] = [:]
    private var playbackTasks: [PlaybackKey: Task<PlayURLData, Error>] = [:]
    private var playbackRequestIDs: [PlaybackKey: UUID] = [:]
    private var activePrefetchCount = 0
    private var prefetchWaiters: [CheckedContinuation<Void, Never>] = []

    /// 用户真正点开视频时走这里，不受预取名额限制；如果同一个请求正在预取，直接复用它。
    func detail(for bvid: String) async throws -> VideoDetail {
        removeExpiredValues()
        if let cached = details[bvid] {
            return cached.value
        }
        if let existingTask = detailTasks[bvid] {
            return try await existingTask.value
        }

        let task = Task { try await BiliAPI.videoDetail(bvid: bvid) }
        detailTasks[bvid] = task
        do {
            let detail = try await task.value
            detailTasks[bvid] = nil
            details[bvid] = CachedValue(value: detail, savedAt: Date())
            trimIfNeeded()
            return detail
        } catch {
            detailTasks[bvid] = nil
            throw error
        }
    }

    func playbackURL(bvid: String, cid: Int) async throws -> PlayURLData {
        removeExpiredValues()
        let key = PlaybackKey(bvid: bvid, cid: cid)
        if let cached = playbackURLs[key] {
            return cached.value
        }
        if let existingTask = playbackTasks[key] {
            if existingTask.isCancelled {
                playbackTasks[key] = nil
                playbackRequestIDs[key] = nil
            } else {
                return try await existingTask.value
            }
        }

        let requestID = UUID()
        let task = Task { try await BiliAPI.playURL(bvid: bvid, cid: cid) }
        playbackTasks[key] = task
        playbackRequestIDs[key] = requestID
        do {
            let payload = try await task.value
            if playbackRequestIDs[key] == requestID {
                playbackTasks[key] = nil
                playbackRequestIDs[key] = nil
                playbackURLs[key] = CachedValue(value: payload, savedAt: Date())
            }
            trimIfNeeded()
            return payload
        } catch {
            if playbackRequestIDs[key] == requestID {
                playbackTasks[key] = nil
                playbackRequestIDs[key] = nil
            }
            throw error
        }
    }

    /// A page-owned playback request is no longer useful after its player is
    /// closed. Cancel the shared in-flight task as well as the caller's wait.
    func cancelPlaybackURL(bvid: String, cid: Int) {
        let key = PlaybackKey(bvid: bvid, cid: cid)
        playbackTasks[key]?.cancel()
        playbackTasks[key] = nil
        playbackRequestIDs[key] = nil
    }

    /// 卡片出现在屏幕上时调用。推荐卡已经有 cid；搜索卡没有，所以先取一次详情。
    func prefetch(bvid: String, cid: Int? = nil) async {
        removeExpiredValues()
        if let cid, playbackURLs[PlaybackKey(bvid: bvid, cid: cid)] != nil { return }
        if cid == nil, let detail = details[bvid]?.value,
           playbackURLs[PlaybackKey(bvid: bvid, cid: detail.cid)] != nil { return }

        guard await acquirePrefetchSlot() else { return }
        defer { releasePrefetchSlot() }
        guard !Task.isCancelled else { return }

        do {
            let resolvedCid: Int
            if let cid {
                resolvedCid = cid
            } else {
                resolvedCid = try await detail(for: bvid).cid
            }
            _ = try await playbackURL(bvid: bvid, cid: resolvedCid)
        } catch {
            // 预取失败不能影响列表使用；用户真正点开时仍会正常重试并显示错误。
        }
    }

    private func acquirePrefetchSlot() async -> Bool {
        if activePrefetchCount < maximumConcurrentPrefetches {
            activePrefetchCount += 1
            return true
        }
        guard prefetchWaiters.count < maximumQueuedPrefetches else { return false }
        await withCheckedContinuation { prefetchWaiters.append($0) }
        return true
    }

    private func releasePrefetchSlot() {
        if prefetchWaiters.isEmpty {
            activePrefetchCount = max(activePrefetchCount - 1, 0)
        } else {
            prefetchWaiters.removeFirst().resume()
        }
    }

    private func removeExpiredValues() {
        let cutoff = Date().addingTimeInterval(-lifetime)
        details = details.filter { $0.value.savedAt >= cutoff }
        playbackURLs = playbackURLs.filter { $0.value.savedAt >= cutoff }
    }

    private func trimIfNeeded() {
        if details.count > maximumEntries,
           let oldest = details.min(by: { $0.value.savedAt < $1.value.savedAt })?.key {
            details[oldest] = nil
        }
        if playbackURLs.count > maximumEntries,
           let oldest = playbackURLs.min(by: { $0.value.savedAt < $1.value.savedAt })?.key {
            playbackURLs[oldest] = nil
        }
    }
}

@MainActor
@Observable
final class PlayerViewModel {
    let bvid: String
    let cid: Int
    let configuration: VideoPlaybackConfiguration
    let session: MPVPlayerSession

    private(set) var isLoading = true
    private(set) var errorMessage: String?
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    /// 已经缓冲到的位置，进度条用它画出比播放位置更靠前的浅色区段。
    private(set) var bufferedTime: Double = 0
    private(set) var hasRenderedFirstFrame = false

    private var isStopped = false
    private let playbackURLLoader: PlaybackURLLoader
    private let systemMediaSessionID = UUID()

    init(
        bvid: String,
        cid: Int,
        configuration: VideoPlaybackConfiguration = .fastStart,
        playbackURLLoader: @escaping PlaybackURLLoader = { bvid, cid in
            try await VideoPreparationCache.shared.playbackURL(bvid: bvid, cid: cid)
        }
    ) {
        self.bvid = bvid
        self.cid = cid
        self.configuration = configuration
        self.playbackURLLoader = playbackURLLoader
        let session = MPVPlayerSession(configuration: configuration)
        self.session = session

        session.onEvent = { [weak self] event in
            self?.handle(event)
        }
    }

    deinit {
        MainActor.assumeIsolated {
            SystemNowPlayingCenter.shared.deactivate(sessionID: systemMediaSessionID)
            session.stop()
        }
    }

    func updateSystemMediaMetadata(title: String, artist: String, artworkURL: URL?) {
        SystemNowPlayingCenter.shared.activate(
            sessionID: systemMediaSessionID,
            metadata: SystemMediaMetadata(
                identifier: bvid,
                title: title,
                artist: artist,
                artworkURL: artworkURL
            ),
            onPlay: { [weak self] in self?.play() },
            onPause: { [weak self] in self?.pause() },
            onToggle: { [weak self] in self?.togglePlayPause() },
            onSeek: { [weak self] position in
                Task { await self?.seek(to: position) }
            }
        )
    }

    func load() async {
        guard !isStopped else { return }
        isLoading = true
        errorMessage = nil
        hasRenderedFirstFrame = false

        do {
            let payload = try await playbackURLLoader(bvid, cid)
            try Task.checkCancellation()
            guard !isStopped else { return }

            let source = try PlaybackSourceBuilder.makeSource(
                from: payload,
                configuration: configuration
            )
            duration = source.duration
            try await session.open(source: source)
        } catch is CancellationError {
            // 离开页面时取消加载属于正常情况，不显示为播放错误。
        } catch {
            if !isStopped {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    /// 真正离开视频页时立即释放播放器、观察器和网络缓冲，保证声音立刻停止。
    func stop() {
        guard !isStopped else { return }
        isStopped = true
        Task {
            await VideoPreparationCache.shared.cancelPlaybackURL(bvid: bvid, cid: cid)
        }
        session.stop()
        SystemNowPlayingCenter.shared.deactivate(sessionID: systemMediaSessionID)
        isPlaying = false
        isLoading = false
    }

    /// 被另一个视频页盖住时调用。只停声音和画面，不释放播放项目。
    func pause() {
        guard isPlaying else { return }
        session.pause()
        isPlaying = false
        SystemNowPlayingCenter.shared.updatePlaybackState(
            isPlaying: false,
            sessionID: systemMediaSessionID
        )
    }

    func play() {
        guard hasRenderedFirstFrame else { return }
        session.play()
        isPlaying = true
        SystemNowPlayingCenter.shared.updatePlaybackState(
            isPlaying: true,
            sessionID: systemMediaSessionID
        )
    }

    func togglePlayPause() {
        guard hasRenderedFirstFrame else { return }
        if isPlaying {
            session.pause()
        } else {
            session.play()
        }
        isPlaying.toggle()
        SystemNowPlayingCenter.shared.updatePlaybackState(
            isPlaying: isPlaying,
            sessionID: systemMediaSessionID
        )
    }

    /// 手指抬起后只调用一次，播放器负责精确到关键帧附近的跳转。
    func seek(to seconds: Double) async {
        let upperBound = duration > 0 ? duration : max(seconds, 0)
        let target = min(max(seconds, 0), upperBound)
        currentTime = target
        SystemNowPlayingCenter.shared.updateElapsed(
            target,
            sessionID: systemMediaSessionID,
            force: true
        )
        await session.seek(to: target)
    }

    private func handle(_ event: PlayerPlaybackEvent) {
        guard !isStopped else { return }

        switch event {
        case .firstFrame:
            hasRenderedFirstFrame = true
            isLoading = false
        case .playing(let playing):
            isPlaying = playing
            SystemNowPlayingCenter.shared.updatePlaybackState(
                isPlaying: playing,
                sessionID: systemMediaSessionID
            )
        case .buffering(let buffering):
            if buffering, !hasRenderedFirstFrame {
                isLoading = true
            }
        case .position(let position):
            currentTime = position
            SystemNowPlayingCenter.shared.updateElapsed(
                position,
                sessionID: systemMediaSessionID
            )
        case .duration(let duration):
            if duration > 0 {
                self.duration = duration
                SystemNowPlayingCenter.shared.updateDuration(
                    duration,
                    sessionID: systemMediaSessionID
                )
            }
        case .buffered(let buffered):
            bufferedTime = max(currentTime + buffered, currentTime)
        case .ended:
            isPlaying = false
            isLoading = false
            SystemNowPlayingCenter.shared.updatePlaybackState(
                isPlaying: false,
                sessionID: systemMediaSessionID
            )
        case .error(let message):
            errorMessage = message
            isPlaying = false
            isLoading = false
            SystemNowPlayingCenter.shared.deactivate(sessionID: systemMediaSessionID)
        }
    }
}
