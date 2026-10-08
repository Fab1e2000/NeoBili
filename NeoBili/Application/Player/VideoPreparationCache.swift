import Foundation

/// 提前保存视频详情和播放地址，点进卡片时就不必重复等待相同请求。
/// 这里只缓存接口返回的小段文字数据，不会提前下载整段视频。
actor VideoPreparationCache {
    static let shared = VideoPreparationCache()

    private struct DetailKey: Hashable, Sendable {
        let sessionID: UUID
        let bvid: String
    }

    private struct PlaybackKey: Hashable, Sendable {
        let sessionID: UUID
        let bvid: String
        let cid: Int
    }

    private struct PlaybackFlight {
        let id: UUID
        let task: Task<PlayURLData, Error>
        var owners: Set<UUID>
        var hasUnownedWaiter: Bool
    }

    private struct DetailFlight {
        let id: UUID
        let task: Task<VideoDetail, Error>
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
    private let scrollPrefetchEnabled: @Sendable () -> Bool
    private let sessionProvider: @Sendable () -> UUID

    private let lifetime: TimeInterval = 5 * 60
    private let maximumEntries = 8
    /// 同时最多预取几个视频。数字越大越占用带宽，会拖慢用户真正点开的那个。
    private let maximumConcurrentPrefetches = 2
    /// 等待队列的上限。超过这个数量说明用户在快速滑动，多余的卡片直接放弃预取。
    private let maximumQueuedPrefetches = 4

    private var activeSessionID: UUID?
    private var details: [DetailKey: CachedValue<VideoDetail>] = [:]
    private var playbackURLs: [PlaybackKey: CachedValue<PlayURLData>] = [:]
    private var detailTasks: [DetailKey: DetailFlight] = [:]
    private var playbackTasks: [PlaybackKey: PlaybackFlight] = [:]
    private var activePrefetchCount = 0
    private var prefetchWaiters: [PrefetchWaiter] = []
    var queuedPrefetchCount: Int { prefetchWaiters.count }

    init(
        detailLoader: @escaping @Sendable (String) async throws -> VideoDetail = {
            try await ApplicationServices.live.video.videoDetail(bvid: $0)
        },
        playbackLoader: @escaping @Sendable (String, Int) async throws -> PlayURLData = {
            try await ApplicationServices.live.video.playURL(bvid: $0, cid: $1)
        },
        scrollPrefetchEnabled: @escaping @Sendable () -> Bool = {
            UserDefaults.standard.bool(forKey: VideoPreparationCache.scrollPrefetchKey)
        },
        sessionProvider: @escaping @Sendable () -> UUID = { ApplicationServices.live.session.currentID() }
    ) {
        self.detailLoader = detailLoader
        self.playbackLoader = playbackLoader
        self.scrollPrefetchEnabled = scrollPrefetchEnabled
        self.sessionProvider = sessionProvider
    }

    /// 用户真正点开视频时走这里，不受预取名额限制；如果同一个请求正在预取，直接复用它。
    func detail(for bvid: String) async throws -> VideoDetail {
        try Task.checkCancellation()
        let key = DetailKey(sessionID: synchronizeSession(), bvid: bvid)
        removeExpiredValues()
        if let cached = details[key] {
            return cached.value
        }
        let flight = detailTasks[key] ?? DetailFlight(id: UUID(), task: Task { try await detailLoader(bvid) })
        detailTasks[key] = flight
        do {
            let detail = try await flight.task.value
            guard sessionProvider() == key.sessionID, !flight.task.isCancelled else { throw CancellationError() }
            if detailTasks[key]?.id == flight.id {
                detailTasks[key] = nil
                details[key] = CachedValue(value: detail, savedAt: Date())
            }
            trimIfNeeded()
            try Task.checkCancellation()
            return detail
        } catch {
            if detailTasks[key]?.id == flight.id { detailTasks[key] = nil }
            throw error
        }
    }

    func playbackURL(bvid: String, cid: Int, ownerID: UUID? = nil,
                     expectedSessionID: UUID? = nil) async throws -> PlayURLData {
        try Task.checkCancellation()
        let sessionID = synchronizeSession()
        guard expectedSessionID == nil || expectedSessionID == sessionID else { throw CancellationError() }
        removeExpiredValues()
        let key = PlaybackKey(sessionID: sessionID, bvid: bvid, cid: cid)
        if let cached = playbackURLs[key] {
            return cached.value
        }
        var flight: PlaybackFlight
        if let existing = playbackTasks[key], !existing.task.isCancelled {
            flight = existing
        } else {
            flight = PlaybackFlight(id: UUID(), task: Task { try await playbackLoader(bvid, cid) },
                                    owners: [], hasUnownedWaiter: false)
        }
        if let ownerID { flight.owners.insert(ownerID) } else { flight.hasUnownedWaiter = true }
        playbackTasks[key] = flight
        do {
            let payload = try await flight.task.value
            guard sessionProvider() == sessionID, !flight.task.isCancelled else { throw CancellationError() }
            if playbackTasks[key]?.id == flight.id {
                playbackTasks[key] = nil
                playbackURLs[key] = CachedValue(value: payload, savedAt: Date())
            }
            trimIfNeeded()
            try Task.checkCancellation()
            return payload
        } catch {
            if playbackTasks[key]?.id == flight.id {
                playbackTasks[key] = nil
            }
            throw error
        }
    }

    /// A page-owned playback request is no longer useful after its player is
    /// closed. Cancel the shared in-flight task as well as the caller's wait.
    func cancelPlaybackURL(bvid: String, cid: Int, ownerID: UUID? = nil, sessionID: UUID? = nil) {
        let key = PlaybackKey(sessionID: sessionID ?? synchronizeSession(), bvid: bvid, cid: cid)
        guard var flight = playbackTasks[key] else { return }
        if let ownerID {
            guard flight.owners.remove(ownerID) != nil else { return }
            if !flight.owners.isEmpty || flight.hasUnownedWaiter {
                playbackTasks[key] = flight
                return
            }
        }
        flight.task.cancel()
        playbackTasks[key] = nil
    }

    func invalidatePlaybackURL(bvid: String, cid: Int, expectedSessionID: UUID? = nil) {
        let sessionID = synchronizeSession()
        guard expectedSessionID == nil || expectedSessionID == sessionID else { return }
        cancelPlaybackURL(bvid: bvid, cid: cid, sessionID: sessionID)
        playbackURLs[PlaybackKey(sessionID: sessionID, bvid: bvid, cid: cid)] = nil
    }

    /// 「滑过时预取」开关，默认关闭：和 PiliPlus 一样只在点开视频时请求播放地址，
    /// B 站服务端就不会看到一串没点开的视频请求。打开后点开更快。
    static let scrollPrefetchKey = "neobili.prefetchOnScroll"

    /// 卡片出现在屏幕上时调用。推荐卡已经有 cid；搜索卡没有，所以先取一次详情。
    /// Reuse the recommendation feed's dwell policy across all scrolling lists.
    /// Cancellation before the delay expires never enters the network queue.
    func prefetchWhenSettled(bvid: String, cid: Int? = nil) async {
        guard scrollPrefetchEnabled() else { return }
        let sessionID = synchronizeSession()
        do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
        guard !Task.isCancelled else { return }
        await prefetch(bvid: bvid, cid: cid, expectedSessionID: sessionID)
    }

    func prefetch(bvid: String, cid: Int? = nil, expectedSessionID: UUID? = nil) async {
        guard !Task.isCancelled else { return }
        let sessionID = synchronizeSession()
        guard expectedSessionID == nil || expectedSessionID == sessionID else { return }
        removeExpiredValues()
        if let cid, playbackURLs[PlaybackKey(sessionID: sessionID, bvid: bvid, cid: cid)] != nil { return }
        if cid == nil, let detail = details[DetailKey(sessionID: sessionID, bvid: bvid)]?.value,
           playbackURLs[PlaybackKey(sessionID: sessionID, bvid: bvid, cid: detail.cid)] != nil { return }

        guard await acquirePrefetchSlot() else { return }
        defer { releasePrefetchSlot(sessionID: sessionID) }
        guard !Task.isCancelled, sessionProvider() == sessionID else { return }

        do {
            let resolvedCid: Int
            if let cid {
                resolvedCid = cid
            } else {
                resolvedCid = try await detail(for: bvid).cid
            }
            try Task.checkCancellation()
            _ = try await playbackURL(bvid: bvid, cid: resolvedCid, expectedSessionID: sessionID)
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

    private func releasePrefetchSlot(sessionID: UUID) {
        guard activeSessionID == sessionID else { return }
        if prefetchWaiters.isEmpty {
            activePrefetchCount = max(activePrefetchCount - 1, 0)
        } else {
            prefetchWaiters.removeFirst().continuation.resume(returning: true)
        }
    }

    /// Cache entries and in-flight requests are credentials-dependent (guest
    /// previews, member quality, private details). Even re-login to the same
    /// account starts a new epoch, and old completions may never repopulate it.
    private func synchronizeSession() -> UUID {
        let sessionID = sessionProvider()
        guard activeSessionID != sessionID else { return sessionID }
        activeSessionID = sessionID
        for flight in detailTasks.values { flight.task.cancel() }
        for flight in playbackTasks.values { flight.task.cancel() }
        detailTasks.removeAll()
        playbackTasks.removeAll()
        details.removeAll()
        playbackURLs.removeAll()
        activePrefetchCount = 0
        let waiters = prefetchWaiters
        prefetchWaiters.removeAll()
        for waiter in waiters { waiter.continuation.resume(returning: false) }
        return sessionID
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
