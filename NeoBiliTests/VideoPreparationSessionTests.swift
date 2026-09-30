import XCTest
import Synchronization
@testable import NeoBili

@MainActor
final class VideoPreparationSessionTests: XCTestCase {
    func testLoginChangeInvalidatesCachedManifestEvenForSameVideo() async throws {
        let session = PreparationTestSession()
        let calls = PreparationManifestProbe()
        let cache = VideoPreparationCache(playbackLoader: { _, _ in await calls.immediate() },
                                         sessionProvider: { session.read() })
        let guest = try await cache.playbackURL(bvid: "same", cid: 1)
        let cachedGuest = try await cache.playbackURL(bvid: "same", cid: 1)
        XCTAssertEqual(guest.quality, cachedGuest.quality)
        session.rotate()
        let loggedIn = try await cache.playbackURL(bvid: "same", cid: 1)
        XCTAssertNotEqual(guest.quality, loggedIn.quality)
        let count = await calls.count
        XCTAssertEqual(count, 2)
    }

    func testLateOldLoginResponseCannotReturnOrReplaceNewCache() async throws {
        let session = PreparationTestSession()
        let calls = PreparationManifestProbe()
        let cache = VideoPreparationCache(playbackLoader: { _, _ in await calls.held() },
                                         sessionProvider: { session.read() })
        let oldSessionID = session.read()
        let old = Task { try await cache.playbackURL(bvid: "same", cid: 1) }
        try await waitUntil { await calls.count == 1 }
        session.rotate()
        let new = Task { try await cache.playbackURL(bvid: "same", cid: 1) }
        try await waitUntil { await calls.count == 2 }
        await calls.release(2)
        let fresh = try await new.value
        await calls.release(1)
        do { _ = try await old.value; XCTFail("old login response returned") }
        catch is CancellationError {}
        let cached = try await cache.playbackURL(bvid: "same", cid: 1)
        XCTAssertEqual(cached.quality, fresh.quality)
        do {
            _ = try await cache.playbackURL(bvid: "same", cid: 1, expectedSessionID: oldSessionID)
            XCTFail("old player acquired credentials-dependent playback data for new login")
        } catch is CancellationError {}
    }

    func testDelayedPreviousPlayerStopCannotCancelNewPlayer() async throws {
        let session = PreparationTestSession()
        let calls = PreparationManifestProbe()
        let cache = VideoPreparationCache(playbackLoader: { _, _ in await calls.held() },
                                         sessionProvider: { session.read() })
        let oldOwner = UUID(), newOwner = UUID()
        let old = Task { try await cache.playbackURL(bvid: "same", cid: 1, ownerID: oldOwner) }
        try await waitUntil { await calls.count == 1 }
        await cache.cancelPlaybackURL(bvid: "same", cid: 1, ownerID: oldOwner, sessionID: session.read())
        let new = Task { try await cache.playbackURL(bvid: "same", cid: 1, ownerID: newOwner) }
        try await waitUntil { await calls.count == 2 }
        await cache.cancelPlaybackURL(bvid: "same", cid: 1, ownerID: oldOwner, sessionID: session.read())
        await calls.release(2)
        let latest = try await new.value
        XCTAssertEqual(latest.quality, 64)
        await calls.release(1)
        do { _ = try await old.value; XCTFail("canceled previous player's payload returned") }
        catch is CancellationError {}
    }

    private func waitUntil(_ predicate: @Sendable () async -> Bool) async throws {
        for _ in 0..<400 {
            if await predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw URLError(.timedOut)
    }
}

private final class PreparationTestSession: Sendable {
    private let value = Mutex(UUID())
    func read() -> UUID { value.withLock { $0 } }
    func rotate() { value.withLock { $0 = UUID() } }
}

private actor PreparationManifestProbe {
    private(set) var count = 0
    private var waiters: [Int: CheckedContinuation<PlayURLData, Never>] = [:]

    func immediate() -> PlayURLData {
        count += 1
        return payload(count)
    }

    func held() async -> PlayURLData {
        count += 1
        let index = count
        return await withCheckedContinuation { waiters[index] = $0 }
    }

    func release(_ index: Int) { waiters.removeValue(forKey: index)?.resume(returning: payload(index)) }

    private func payload(_ index: Int) -> PlayURLData {
        PlayURLData(quality: index * 32, acceptQuality: nil, acceptDescription: nil,
                    durl: nil, dash: nil, vVoucher: nil)
    }
}
