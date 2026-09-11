import Foundation

// Only API payload and network boundaries are stubs; scheduling/cache code is
// compiled directly from the app's VideoPreparationCache.swift.
struct VideoDetail: Sendable { let cid: Int }
struct PlayURLData: Sendable { let quality: Int }
enum BiliAPI {
    static func videoDetail(bvid: String) async throws -> VideoDetail { throw URLError(.unsupportedURL) }
    static func playURL(bvid: String, cid: Int) async throws -> PlayURLData { throw URLError(.unsupportedURL) }
}

private actor Requests {
    var details: [String] = []
    var playback: [String] = []
    var completed: Set<String> = []
    private var held: [CheckedContinuation<Void, Never>] = []

    func detail(_ bvid: String) async -> VideoDetail {
        details.append(bvid)
        await withCheckedContinuation { held.append($0) }
        return VideoDetail(cid: 1)
    }
    func play(_ bvid: String) -> PlayURLData {
        playback.append(bvid)
        return PlayURLData(quality: 64)
    }
    func immediateDetail(_ bvid: String) -> VideoDetail {
        details.append(bvid)
        return VideoDetail(cid: 1)
    }
    func markCompleted(_ id: String) { completed.insert(id) }
    func release() {
        let pending = held
        held.removeAll()
        for continuation in pending { continuation.resume() }
    }
}

@main
struct VideoPreparationRegression {
    static func waitUntil(_ condition: @Sendable () async -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while !(await condition()) {
            precondition(ProcessInfo.processInfo.systemUptime < deadline, "Timed out waiting for cache state")
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    static func main() async throws {
        let requests = Requests()
        let cache = VideoPreparationCache(detailLoader: { await requests.detail($0) },
                                         playbackLoader: { bvid, _ in await requests.play(bvid) })
        let first = Task { await cache.prefetch(bvid: "first") }
        let second = Task { await cache.prefetch(bvid: "second") }
        try await waitUntil { await requests.details.count == 2 }
        let queued = Task {
            await cache.prefetch(bvid: "queued")
            await requests.markCompleted("queued")
        }
        try await waitUntil { await cache.queuedPrefetchCount == 1 }
        queued.cancel()
        try await waitUntil { await requests.completed.contains("queued") }
        let queuedCount = await cache.queuedPrefetchCount
        precondition(queuedCount == 0, "Cancellation must free queued work before network requests finish")
        first.cancel()
        await requests.release()
        await first.value
        await second.value
        await queued.value
        let playbackCalls = await requests.playback
        let detailCalls = await requests.details
        precondition(playbackCalls == ["second"], "A cancelled card cannot continue fetching play URLs after detail")
        precondition(detailCalls.count == 2, "A queued cancelled card must not start any network work")
        _ = try await cache.detail(for: "first")
        let afterReuse = await requests.details.count
        precondition(afterReuse == 2, "Completed shared detail remains reusable by an actual video open")
        let direct = Requests()
        let directCache = VideoPreparationCache(detailLoader: { await direct.immediateDetail($0) },
                                               playbackLoader: { bvid, _ in await direct.play(bvid) })
        let cancelledDetail = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try? await directCache.detail(for: "already-cancelled")
        }
        let cancelledPlayback = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try? await directCache.playbackURL(bvid: "already-cancelled", cid: 1)
        }
        await cancelledDetail.value
        await cancelledPlayback.value
        let cancelledCalls = await direct.details.count + direct.playback.count
        precondition(cancelledCalls == 0, "Already-cancelled foreground callers cannot create unstructured network work")
        print("PASS  Queued cancellation finishes while both network slots are occupied")
        print("PLAY_URL_REQUESTS_AFTER_CANCELLED_DETAIL legacy=2 fixed=1")
        print("PASS  Shared completed detail still serves later foreground opens")
        print("PASS  Already-cancelled direct detail/playback callers start zero API requests")
        print("ALL VIDEO PREPARATION CHECKS PASS")
    }
}
