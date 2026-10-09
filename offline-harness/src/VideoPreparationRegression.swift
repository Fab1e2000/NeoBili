import Foundation
import Synchronization

// Only API payload and network boundaries are stubs; scheduling/cache code is
// compiled directly from the app's VideoPreparationCache.swift.
struct VideoDetail: Sendable { let cid: Int }
struct PlayURLData: Sendable { let quality: Int }
actor DeviceIdentity {
    static let shared = DeviceIdentity()
    nonisolated let loginSessionID = UUID()
}
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
        try await testSessionBoundCacheAndLateCompletions()
        try await testOldOwnerCannotCancelReopenedVideo()
        try await testAccountSwitchDiscardsSettlingPrefetch()
        print("PASS  Queued cancellation finishes while both network slots are occupied")
        print("PLAY_URL_REQUESTS_AFTER_CANCELLED_DETAIL legacy=2 fixed=1")
        print("PASS  Shared completed detail still serves later foreground opens")
        print("PASS  Already-cancelled direct detail/playback callers start zero API requests")
        print("PASS  Login epochs isolate cached details/playback URLs and reject late old-account responses")
        print("PASS  Delayed old-player cancellation cannot cancel a reopened video's new request")
        print("PASS  A settling old-account card cannot start playback preparation after account switch")
        print("ALL VIDEO PREPARATION CHECKS PASS")
    }

    private static func testSessionBoundCacheAndLateCompletions() async throws {
        let session = SessionEpoch()
        let calls = ControlledRequests()
        let cache = VideoPreparationCache(detailLoader: { _ in await calls.detail() },
            playbackLoader: { _, _ in await calls.play() }, sessionProvider: { session.read() })
        let oldPlayback = Task { try await cache.playbackURL(bvid: "same", cid: 1) }
        let oldDetail = Task { try await cache.detail(for: "same") }
        try await waitUntil { await calls.hasCounts(play: 1, detail: 1) }
        let oldSessionID = session.read()
        session.rotate()
        let newPlayback = Task { try await cache.playbackURL(bvid: "same", cid: 1) }
        let newDetail = Task { try await cache.detail(for: "same") }
        try await waitUntil { await calls.hasCounts(play: 2, detail: 2) }
        await calls.releasePlay(2, quality: 80)
        await calls.releaseDetail(2, cid: 2)
        let latestPlayback = try await newPlayback.value
        let latestDetail = try await newDetail.value
        precondition(latestPlayback.quality == 80 && latestDetail.cid == 2)
        await calls.releasePlay(1, quality: 32)
        await calls.releaseDetail(1, cid: 1)
        do { _ = try await oldPlayback.value; fatalError("old-account playback response returned") }
        catch is CancellationError {}
        do { _ = try await oldDetail.value; fatalError("old-account detail response returned") }
        catch is CancellationError {}
        let cachedPlayback = try await cache.playbackURL(bvid: "same", cid: 1)
        let cachedDetail = try await cache.detail(for: "same")
        precondition(cachedPlayback.quality == 80 && cachedDetail.cid == 2, "old responses must not replace the new session's cache")
        do {
            _ = try await cache.playbackURL(bvid: "same", cid: 1, expectedSessionID: oldSessionID)
            fatalError("stopped old-account player acquired a new-account URL")
        } catch is CancellationError {}
        let count = await calls.playCount
        precondition(count == 2, "cached value or rejected old owner must not start another request")
    }

    private static func testOldOwnerCannotCancelReopenedVideo() async throws {
        let session = SessionEpoch()
        let calls = ControlledRequests()
        let cache = VideoPreparationCache(playbackLoader: { _, _ in await calls.play() },
                                         sessionProvider: { session.read() })
        let oldOwner = UUID(), newOwner = UUID()
        let first = Task { try await cache.playbackURL(bvid: "reopened", cid: 1, ownerID: oldOwner) }
        try await waitUntil { await calls.playCount == 1 }
        await cache.cancelPlaybackURL(bvid: "reopened", cid: 1, ownerID: oldOwner, sessionID: session.read())
        let second = Task { try await cache.playbackURL(bvid: "reopened", cid: 1, ownerID: newOwner) }
        try await waitUntil { await calls.playCount == 2 }
        // Simulates an old stop's asynchronously scheduled cleanup arriving late.
        await cache.cancelPlaybackURL(bvid: "reopened", cid: 1, ownerID: oldOwner, sessionID: session.read())
        await calls.releasePlay(2, quality: 80)
        let resumed = try await second.value
        precondition(resumed.quality == 80, "old owner canceled the newly opened video")
        await calls.releasePlay(1, quality: 32)
        do { _ = try await first.value; fatalError("canceled old playback returned") }
        catch is CancellationError {}
        let cached = try await cache.playbackURL(bvid: "reopened", cid: 1)
        precondition(cached.quality == 80, "late canceled payload polluted the cache")
    }

    private static func testAccountSwitchDiscardsSettlingPrefetch() async throws {
        let session = SessionEpoch()
        let calls = Requests()
        let cache = VideoPreparationCache(detailLoader: { await calls.immediateDetail($0) },
            playbackLoader: { bvid, _ in await calls.play(bvid) }, scrollPrefetchEnabled: { true },
            sessionProvider: { session.read() })
        let prefetch = Task { await cache.prefetchWhenSettled(bvid: "old-account-card", cid: 1) }
        try await Task.sleep(for: .milliseconds(30))
        session.rotate()
        await prefetch.value
        let count = await calls.playback.count
        precondition(count == 0, "old-account settling card started a new-account playback request")
    }
}

private final class SessionEpoch: Sendable {
    private let value = Mutex(UUID())
    func read() -> UUID { value.withLock { $0 } }
    func rotate() { value.withLock { $0 = UUID() } }
}

private actor ControlledRequests {
    private(set) var playCount = 0
    private(set) var detailCount = 0
    private var playWaiters: [Int: CheckedContinuation<PlayURLData, Never>] = [:]
    private var detailWaiters: [Int: CheckedContinuation<VideoDetail, Never>] = [:]

    func hasCounts(play: Int, detail: Int) -> Bool { playCount == play && detailCount == detail }

    func play() async -> PlayURLData {
        playCount += 1
        let index = playCount
        return await withCheckedContinuation { playWaiters[index] = $0 }
    }
    func detail() async -> VideoDetail {
        detailCount += 1
        let index = detailCount
        return await withCheckedContinuation { detailWaiters[index] = $0 }
    }
    func releasePlay(_ index: Int, quality: Int) {
        playWaiters.removeValue(forKey: index)?.resume(returning: PlayURLData(quality: quality))
    }
    func releaseDetail(_ index: Int, cid: Int) {
        detailWaiters.removeValue(forKey: index)?.resume(returning: VideoDetail(cid: cid))
    }
}

struct ApplicationServices: Sendable {
    static let live = ApplicationServices()
    var video: BiliAPI.Type { BiliAPI.self }
    var session: Session { Session() }
    struct Session: Sendable {
        func currentID() -> UUID { DeviceIdentity.shared.loginSessionID }
    }
}
