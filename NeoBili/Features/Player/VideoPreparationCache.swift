import Foundation

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

    private struct PrefetchWaiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let detailLoader: @Sendable (String) async throws -> VideoDetail
    private let playbackLoader: @Sendable (String, Int) async throws -> PlayURLData

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
    private var prefetchWaiters: [PrefetchWaiter] = []
    var queuedPrefetchCount: Int { prefetchWaiters.count }

    init(
        detailLoader: @escaping @Sendable (String) async throws -> VideoDetail = {
            try await BiliAPI.videoDetail(bvid: $0)
        },
        playbackLoader: @escaping @Sendable (String, Int) async throws -> PlayURLData = {
            try await BiliAPI.playURL(bvid: $0, cid: $1)
        }
    ) {
        self.detailLoader = detailLoader
        self.playbackLoader = playbackLoader
    }

    /// 用户真正点开视频时走这里，不受预取名额限制；如果同一个请求正在预取，直接复用它。
    func detail(for bvid: String) async throws -> VideoDetail {
        try Task.checkCancellation()
        removeExpiredValues()
        if let cached = details[bvid] {
            return cached.value
        }
        if let existingTask = detailTasks[bvid] {
            return try await existingTask.value
        }

        let task = Task { try await detailLoader(bvid) }
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
        try Task.checkCancellation()
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
        let task = Task { try await playbackLoader(bvid, cid) }
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

    func invalidatePlaybackURL(bvid: String, cid: Int) {
        cancelPlaybackURL(bvid: bvid, cid: cid)
        playbackURLs[PlaybackKey(bvid: bvid, cid: cid)] = nil
    }

    /// 卡片出现在屏幕上时调用。推荐卡已经有 cid；搜索卡没有，所以先取一次详情。
    func prefetch(bvid: String, cid: Int? = nil) async {
        guard !Task.isCancelled else { return }
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
            try Task.checkCancellation()
            _ = try await playbackURL(bvid: bvid, cid: resolvedCid)
        } catch {
            // 预取失败不能影响列表使用；用户真正点开时仍会正常重试并显示错误。
        }
    }

    private func acquirePrefetchSlot() async -> Bool {
        guard !Task.isCancelled else { return false }
        if activePrefetchCount < maximumConcurrentPrefetches {
            activePrefetchCount += 1
            return true
        }
        guard prefetchWaiters.count < maximumQueuedPrefetches else { return false }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                } else {
                    prefetchWaiters.append(PrefetchWaiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelPrefetchWaiter(id) }
        }
    }

    private func cancelPrefetchWaiter(_ id: UUID) {
        guard let index = prefetchWaiters.firstIndex(where: { $0.id == id }) else { return }
        prefetchWaiters.remove(at: index).continuation.resume(returning: false)
    }

    private func releasePrefetchSlot() {
        if prefetchWaiters.isEmpty {
            activePrefetchCount = max(activePrefetchCount - 1, 0)
        } else {
            prefetchWaiters.removeFirst().continuation.resume(returning: true)
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
