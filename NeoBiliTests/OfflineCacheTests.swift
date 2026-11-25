import XCTest
import Observation
@testable import NeoBili
@testable import NeoBiliDomain
@testable import NeoBiliData

final class OfflineCacheTests: XCTestCase {
    private func video(_ cid: Int = 1) -> OfflineVideo {
        .init(bvid: "BV-offline", cid: cid, aid: 1, title: "缓存测试", partTitle: "P\(cid)", author: "作者",
              cover: nil, duration: 12, groupID: "video:BV-offline", groupTitle: "缓存测试", order: cid)
    }
    private func resources(subtitle: Bool = true) -> OfflinePreparedResources {
        var resources: [OfflineResource] = [
            .init(id: "video-0", kind: .video, url: URL(string: "https://example.invalid/video.mp4")!, filename: "video.mp4"),
            .init(id: "danmaku", kind: .danmaku, url: URL(string: "https://example.invalid/dm")!, filename: "danmaku.xml")
        ]
        if subtitle {
            resources.append(.init(id: "subtitle-zh", kind: .subtitle, url: URL(string: "https://example.invalid/sub")!,
                filename: "sub.json", language: "zh-CN", title: "中文"))
        }
        return .init(resources: resources, width: 128, height: 72)
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func waitFor(_ condition: @escaping () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for cache state", file: file, line: line)
    }

    func testFailedCancelCanBeRetriedWithoutLosingTheTransfer() async throws {
        let root = try directory(), transport = CacheTestTransport(), plan = resources()
        let repo = OfflineCacheRepository(directory: root, transport: transport, prepare: { _ in plan }, accountID: { nil })
        await repo.start()
        await transport.network()
        try await repo.enqueue([video()], quality: 80, audioQuality: 0, replace: false)
        try await waitFor { await transport.count() > 0 }
        let file = root.appendingPathComponent("manifest.json")
        let backup = root.appendingPathComponent("saved.json")
        try FileManager.default.moveItem(at: file, to: backup)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        do {
            try await repo.cancel(video().id)
            XCTFail("Cancellation should report the manifest write failure")
        } catch { }
        let pending = await repo.snapshot().tasks
        XCTAssertEqual(pending.map(\.id), [video().id])
        let active = await transport.existingTokens()
        XCTAssertFalse(active.isEmpty)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: backup, to: file)
        try await repo.cancel(video().id)
        let remaining = await transport.existingTokens()
        XCTAssertTrue(remaining.isEmpty)
        let restored = OfflineCacheRepository(directory: root, transport: CacheTestTransport(), prepare: { _ in plan }, accountID: { nil })
        await restored.start()
        let tasks = await restored.snapshot().tasks
        XCTAssertTrue(tasks.isEmpty)
    }

    func testOnlinePlaybackLimitsNewTransfersWithoutCancellingExistingOnes() async throws {
        let transfer = CacheTestTransport(), plan = resources(subtitle: false)
        let repo = OfflineCacheRepository(directory: try directory(), transport: transfer,
            prepare: { _ in plan }, accountID: { nil })
        await repo.start()
        await transfer.network()
        await repo.service.setOnlinePlaybackActive(true)
        try await repo.enqueue((1...5).map(video), quality: 80, audioQuality: 0, replace: false)
        try await waitFor {
            let tasks = await repo.snapshot().tasks
            return tasks.count == 5 && tasks.allSatisfy { !$0.resources.isEmpty }
        }
        try await waitFor { await transfer.count() >= 2 }
        let limited = await transfer.existingTokens()
        XCTAssertEqual(limited.count, 2)

        await repo.service.setOnlinePlaybackActive(false)
        try await waitFor { await transfer.count() >= 8 }
        let full = await transfer.existingTokens()
        XCTAssertEqual(full.count, 8)
        XCTAssertTrue(limited.isSubset(of: full))

        await repo.service.setOnlinePlaybackActive(true)
        let stillRunning = await transfer.existingTokens()
        XCTAssertEqual(stillRunning, full)

        let key = try XCTUnwrap(full.first { $0.hasSuffix("/video-0") })
        try await transfer.finish(token: key, data: Data("\0\0\0\u{18}ftypisom".utf8))
        try await waitFor { await repo.snapshot().tasks.flatMap(\.resources).contains(where: \.isComplete) }
        let starts = await transfer.count()
        XCTAssertEqual(starts, 8)
    }

    @MainActor func testDownloadProgressDoesNotInvalidateLibraryOrTaskCount() async {
        let store = OfflineCacheStore(service: .init())
        var completed = OfflineCacheEntry(video: video(), quality: 80, accountID: nil)
        completed.state = .completed
        var task = OfflineCacheEntry(video: video(2), quality: 80, accountID: nil)
        task.resources = resources().resources
        store.snapshot.completed = [completed]
        store.snapshot.tasks = [task]

        let libraryChanged = expectation(description: "Library should stay stable during progress")
        libraryChanged.isInverted = true
        withObservationTracking {
            _ = store.entries(in: completed.video.groupID)
            _ = store.completedCovers
            _ = store.taskCount
        } onChange: {
            libraryChanged.fulfill()
        }
        let tasksChanged = expectation(description: "Download readers receive the new progress")
        withObservationTracking {
            _ = store.tasks
        } onChange: {
            tasksChanged.fulfill()
        }
        task.resources[0].receivedBytes = 1024
        store.snapshot.tasks = [task]
        await fulfillment(of: [tasksChanged, libraryChanged], timeout: 0.05)
        XCTAssertEqual(store.tasks.first?.receivedBytes, 1024)
    }

    func testInvalidBatchLeavesQueueEmpty() async throws {
        let plan = resources()
        let repo = OfflineCacheRepository(directory: try directory(), transport: CacheTestTransport(),
            prepare: { _ in plan }, accountID: { nil })
        do {
            try await repo.enqueue([video(), video(0)], quality: 80, audioQuality: 0, replace: false)
            XCTFail("Invalid part must reject the batch")
        } catch OfflineCacheError.invalidResource { }
        let tasks = await repo.snapshot().tasks
        XCTAssertTrue(tasks.isEmpty)
    }

    func testRequiresAllResourcesAndRestoresCompletedCacheWithoutNetwork() async throws {
        let root = try directory(), transfer = CacheTestTransport()
        var plan = resources()
        plan.chapters = [.init(from: 0, to: 5, title: "开场"), .init(from: 5, to: 12, title: "正片")]
        plan.resources.append(.init(id: "cover", kind: .cover, url: URL(string: "https://example.invalid/cover.png")!, filename: "cover.png"))
        let prepared = plan
        let repo = OfflineCacheRepository(directory: root, transport: transfer, prepare: { _ in prepared }, accountID: { nil })
        await repo.start(); await transfer.network()
        try await repo.enqueue([video()], quality: 80, audioQuality: 0, replace: false)
        try await waitFor { await transfer.count() == 4 }
        try await transfer.finish(kind: "video-0", data: Data("\0\0\0\u{18}ftypisom-test-video".utf8))
        try await transfer.finish(kind: "danmaku", data: Data("<i><d p=\"1,1,25,16777215\">离线弹幕</d></i>".utf8))
        try await waitFor { await repo.snapshot().tasks.first?.resources.filter(\.isComplete).count == 2 }
        let incomplete = await repo.snapshot()
        XCTAssertTrue(incomplete.completed.isEmpty)
        try await transfer.finish(kind: "cover", data: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!)
        try await transfer.finish(kind: "subtitle-zh", data: Data(#"{"body":[{"from":0,"to":4,"content":"字幕"}]}"#.utf8))
        try await waitFor { await repo.snapshot().completed.count == 1 }
        let descriptor = try await repo.service.playback(video().id)
        XCTAssertTrue(descriptor.videoURLs.allSatisfy(\.isFileURL))
        XCTAssertEqual(descriptor.danmaku.count, 1)
        XCTAssertEqual(descriptor.subtitles.first?.text(at: 2), "字幕")
        XCTAssertEqual(descriptor.entry.chapters, prepared.chapters)
        await repo.service.releasePlayback(descriptor.leaseID)

        let restoredTransfer = CacheTestTransport()
        let restored = OfflineCacheRepository(directory: root, transport: restoredTransfer,
            prepare: { _ in XCTFail("Completed media must never prepare again"); throw OfflineCacheError.unconfigured }, accountID: { nil })
        await restored.start()
        let saved = try await restored.service.playback(video().id)
        XCTAssertEqual(saved.entry.quality, 80)
        XCTAssertEqual(saved.entry.chapters, prepared.chapters)
        let restoredSnapshot = await restored.snapshot()
        let cover = try XCTUnwrap(restoredSnapshot.coverURLs[saved.entry.generation])
        XCTAssertEqual(cover, saved.coverURL)
        XCTAssertTrue(cover.isFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cover.path))
        let starts = await restoredTransfer.count()
        XCTAssertEqual(starts, 0)
    }

    func testRestoresLegacyManifestWithoutChapters() async throws {
        let root = try directory()
        var entry = OfflineCacheEntry(video: video(), quality: 80, accountID: nil)
        entry.state = .completed
        var legacyEntry = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        legacyEntry.removeValue(forKey: "chapters")
        let manifest: [String: Any] = ["completed": [entry.id: legacyEntry], "pending": [:], "retired": []]
        try JSONSerialization.data(withJSONObject: manifest).write(to: root.appendingPathComponent("manifest.json"))

        let repo = OfflineCacheRepository(directory: root, transport: CacheTestTransport(),
            prepare: { _ in throw OfflineCacheError.unconfigured }, accountID: { nil })
        await repo.start()
        let snapshot = await repo.snapshot()
        XCTAssertNil(snapshot.error)
        XCTAssertEqual(snapshot.completed, [entry])
    }

    func testSubtitleFailureStaysPendingAndOtherVideoCompletes() async throws {
        let root = try directory(), transfer = CacheTestTransport(), plan = resources()
        let repo = OfflineCacheRepository(directory: root, transport: transfer, prepare: { _ in plan }, accountID: { nil })
        await repo.start(); await transfer.network()
        try await repo.enqueue([video(1), video(2)], quality: 80, audioQuality: 0, replace: false)
        try await waitFor { await transfer.count() == 6 }
        let pending = await repo.snapshot().tasks
        for entry in pending {
            func key(_ id: String) -> String {
                let resource = entry.resources.first { $0.id == id }!
                return entry.generation.uuidString + "/" + resource.transferID.uuidString + "/" + id
            }
            try await transfer.finish(token: key("video-0"), data: Data("\0\0\0\u{18}ftypisom".utf8))
            try await transfer.finish(token: key("danmaku"), data: Data("<i/>".utf8))
            try await transfer.finish(token: key("subtitle-zh"),
                data: Data((entry.video.cid == 1 ? "invalid" : #"{"body":[]}"#).utf8))
        }
        try await waitFor {
            let value = await repo.snapshot()
            return value.completed.count == 1 && value.tasks.first?.state == .failed
        }
        let value = await repo.snapshot()
        XCTAssertEqual(value.completed.first?.video.cid, 2)
        XCTAssertEqual(value.tasks.first?.video.cid, 1)
    }

    func testWiFiPolicyManualPauseAndAccountChanges() async throws {
        let root = try directory(), transfer = CacheTestTransport(), account = CacheTestAccount(), plan = resources(subtitle: false)
        let repo = OfflineCacheRepository(directory: root, transport: transfer, prepare: { _ in plan }, accountID: { await account.value })
        await repo.start(); await transfer.network(cellular: true)
        try await repo.enqueue([video()], quality: 80, audioQuality: 0, replace: false)
        try await waitFor { await repo.snapshot().tasks.first?.state == .waitingForNetwork }
        let zero = await transfer.count(); XCTAssertEqual(zero, 0)
        try await repo.service.resume(video().id, true)
        try await waitFor { await transfer.count() == 2 }
        let starts = await transfer.requests
        XCTAssertTrue(starts.allSatisfy(\.cellular))
        try await repo.service.pause(video().id)
        await transfer.network()
        let paused = await repo.snapshot(); XCTAssertEqual(paused.tasks.first?.state, .paused)
        await account.change("another")
        await repo.accountDidChange()
        let changed = await repo.snapshot(); XCTAssertEqual(changed.tasks.first?.state, .accountPaused)
        try await repo.service.resume(video().id, false)
        try await waitFor { await repo.snapshot().tasks.first?.state == .downloading }
        let resumed = await repo.snapshot(); XCTAssertEqual(resumed.tasks.first?.accountID, "another")
    }

    func testReplacementRetainsOldVersionUntilCompleteAndPlaybackLeaseEnds() async throws {
        let root = try directory(), transfer = CacheTestTransport(), plan = resources(subtitle: false)
        let repo = OfflineCacheRepository(directory: root, transport: transfer, prepare: { _ in plan }, accountID: { nil })
        await repo.start(); await transfer.network()
        try await repo.enqueue([video()], quality: 80, audioQuality: 0, replace: false)
        try await waitFor { await transfer.count() == 2 }
        try await transfer.finish(kind: "video-0", data: Data("\0\0\0\u{18}ftypisom".utf8))
        try await transfer.finish(kind: "danmaku", data: Data("<i/>".utf8))
        try await waitFor { await repo.snapshot().completed.count == 1 }
        let old = try await repo.service.playback(video().id)
        try await repo.enqueue([video()], quality: 80, audioQuality: 30280, replace: true)
        let duplicate = await repo.snapshot()
        XCTAssertTrue(duplicate.tasks.isEmpty)
        XCTAssertEqual(duplicate.completed.first?.generation, old.entry.generation)
        try await repo.enqueue([video()], quality: 120, audioQuality: 0, replace: true)
        try await waitFor { await transfer.count() == 4 }
        try await transfer.finish(kind: "video-0", data: Data("invalid media".utf8))
        try await waitFor { await repo.snapshot().tasks.first?.state == .failed }
        let playable = try await repo.service.playback(video().id)
        XCTAssertEqual(playable.entry.generation, old.entry.generation)
        await repo.service.releasePlayback(playable.leaseID)
        try await repo.enqueue([video()], quality: 64, audioQuality: 0, replace: true)
        try await waitFor { await transfer.count() == 6 }
        let during = await repo.snapshot(); XCTAssertEqual(during.completed.first?.quality, 80)
        try await transfer.finish(kind: "video-0", data: Data("\0\0\0\u{18}ftypisom-new".utf8))
        try await transfer.finish(kind: "danmaku", data: Data("<i/>".utf8))
        try await waitFor { await repo.snapshot().completed.first?.quality == 64 }
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.videoURLs[0].path))
        await repo.service.releasePlayback(old.leaseID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.videoURLs[0].path))
        try await repo.service.delete([video().id])
        let empty = await repo.snapshot(); XCTAssertTrue(empty.completed.isEmpty)
    }

    func testUnavailableQualityFailsWithoutDowngrade() throws {
        let payload = try JSONDecoder().decode(PlayURLData.self, from: Data(#"{"quality":64,"durl":[{"url":"https://example.invalid/movie.mp4"}]}"#.utf8))
        XCTAssertThrowsError(try OfflineCachePreparation.mediaResources(payload, quality: 80, audioQuality: 0))
        let accepted = try OfflineCachePreparation.mediaResources(payload, quality: 64, audioQuality: 0)
        XCTAssertEqual(accepted.resources.count, 1)
    }

    func testDiskFullKeepsTaskAndStartsNoTransfer() async throws {
        let root = try directory(), transfer = CacheTestTransport(), plan = resources(subtitle: false)
        let repo = OfflineCacheRepository(directory: root, transport: transfer, prepare: { _ in plan }, accountID: { nil }, capacity: { 0 })
        await repo.start(); await transfer.network()
        try await repo.enqueue([video()], quality: 80, audioQuality: 0, replace: false)
        try await waitFor { await repo.snapshot().tasks.first?.state == .failed }
        let count = await transfer.count(); XCTAssertEqual(count, 0)
        let state = await repo.snapshot(); XCTAssertTrue(state.completed.isEmpty)
        XCTAssertEqual(state.tasks.first?.message, OfflineCacheError.storageFull.localizedDescription)
    }

    func testMalformedDanmakuIsDistinctFromEmpty() throws {
        XCTAssertTrue(try DanmakuLoader.parseValidated(Data("<i/>".utf8)).isEmpty)
        XCTAssertThrowsError(try DanmakuLoader.parseValidated(Data("<i><d".utf8)))
        XCTAssertThrowsError(try DanmakuLoader.parseValidated(Data("<html/>".utf8)))
    }

    func testPausePersistsAndLateCallbackCannotCompleteResumedTask() async throws {
        let root = try directory(), transfer = CacheTestTransport(), plan = resources(subtitle: false)
        let repo = OfflineCacheRepository(directory: root, transport: transfer, prepare: { _ in plan }, accountID: { nil })
        await repo.start(); await transfer.network()
        try await repo.enqueue([video()], quality: 80, audioQuality: 0, replace: false)
        try await waitFor { await transfer.count() == 2 }
        let old = await transfer.requests.first { $0.token.hasSuffix("/video-0") }!
        try await repo.service.pause(video().id)
        let restoredTransfer = CacheTestTransport()
        let restored = OfflineCacheRepository(directory: root, transport: restoredTransfer,
            prepare: { _ in XCTFail("Manual pause must preserve prepared resources"); return plan }, accountID: { nil })
        await restored.start(); await restoredTransfer.network()
        let paused = await restored.snapshot()
        XCTAssertEqual(paused.tasks.first?.state, .paused)
        XCTAssertTrue(paused.tasks.first?.resources.allSatisfy { $0.resumeData != nil } == true)
        try await restored.service.resume(video().id, false)
        try await waitFor { await restoredTransfer.count() == 2 }
        let resumed = await restoredTransfer.requests
        XCTAssertTrue(resumed.allSatisfy { $0.resumeData != nil })
        XCTAssertFalse(resumed.contains { $0.token == old.token })
        try await restoredTransfer.finish(token: old.token, data: Data("\0\0\0\u{18}ftypold".utf8))
        await restoredTransfer.failure(resumed.first { $0.token.hasSuffix("/video-0") }!.token)
        try await waitFor { await restoredTransfer.count() == 3 }
        let restarted = await restoredTransfer.requests.last!
        XCTAssertNil(restarted.resumeData)
        let current = await restored.snapshot()
        XCTAssertTrue(current.completed.isEmpty)
        XCTAssertTrue(current.tasks.first?.resources.allSatisfy { !$0.isComplete } == true)
        try await restored.service.cancel(video().id)
        let cancelled = await restored.snapshot()
        XCTAssertTrue(cancelled.tasks.isEmpty)
    }

    func testInterruptedNetworkResumesAutomaticallyWithSavedData() async throws {
        let root = try directory(), transfer = CacheTestTransport(), plan = resources(subtitle: false)
        let repo = OfflineCacheRepository(directory: root, transport: transfer, prepare: { _ in plan }, accountID: { nil })
        await repo.start(); await transfer.network()
        try await repo.enqueue([video()], quality: 80, audioQuality: 0, replace: false)
        try await waitFor { await transfer.count() == 2 }
        let key = await transfer.requests.first!.token
        await transfer.network(available: false)
        await transfer.failure(key, resumeData: Data("resume-after-network".utf8))
        try await waitFor { await repo.snapshot().tasks.first?.state == .waitingForNetwork }
        await transfer.network()
        try await waitFor { await transfer.count() == 3 }
        let restarted = await transfer.requests.last!
        XCTAssertEqual(restarted.resumeData, Data("resume-after-network".utf8))
    }

    func testBackgroundCompletionDuringRestoreIsRetained() async throws {
        let root = try directory(), transfer = CacheTestTransport(), plan = resources(subtitle: false)
        let repo = OfflineCacheRepository(directory: root, transport: transfer, prepare: { _ in plan }, accountID: { nil })
        await repo.start(); await transfer.network()
        try await repo.enqueue([video()], quality: 80, audioQuality: 0, replace: false)
        try await waitFor { await transfer.count() == 2 }
        let requests = await transfer.requests
        let restoredTransfer = CacheTestTransport()
        for request in requests {
            try await restoredTransfer.finish(token: request.token, data: Data((request.token.hasSuffix("/danmaku") ? "<i/>" : "\0\0\0\u{18}ftypisom").utf8))
        }
        let restored = OfflineCacheRepository(directory: root, transport: restoredTransfer,
            prepare: { _ in XCTFail("Restored completion must use existing resources"); return plan }, accountID: { nil })
        await restored.start()
        try await waitFor { await restored.snapshot().completed.count == 1 }
        let result = try await restored.service.playback(video().id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.videoURLs[0].path))
        let started = await restoredTransfer.count()
        XCTAssertEqual(started, 0)
    }

    func testAccountChangeDuringLaunchKeepsPendingDownloadsPaused() async throws {
        let root = try directory(), transfer = CacheTestTransport(), plan = resources(subtitle: false)
        let repo = OfflineCacheRepository(directory: root, transport: transfer, prepare: { _ in plan }, accountID: { nil })
        await repo.start(); await transfer.network()
        try await repo.enqueue([video()], quality: 80, audioQuality: 0, replace: false)
        try await waitFor { await transfer.count() == 2 }
        let restoredTransfer = CacheTestTransport()
        for request in await transfer.requests {
            try await restoredTransfer.finish(token: request.token, data: Data((request.token.hasSuffix("/danmaku") ? "<i/>" : "\0\0\0\u{18}ftypisom").utf8))
        }
        let restored = OfflineCacheRepository(directory: root, transport: restoredTransfer,
            prepare: { _ in XCTFail("Account changes require explicit resume"); return plan }, accountID: { "new-account" })
        await restored.start()
        let result = await restored.snapshot()
        XCTAssertTrue(result.completed.isEmpty)
        XCTAssertEqual(result.tasks.first?.state, .accountPaused)
    }

    @MainActor func testOfflineProgressDoesNotChangeOnlineProgress() {
        let name = "offline-test-\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let online = PlaybackProgressStore(defaults: defaults)
        let offline = PlaybackProgressStore(defaults: defaults, storageNamespace: "offline")
        online.save(bvid: "BV", cid: 1, position: 20, duration: 100)
        offline.save(bvid: "BV", cid: 1, position: 70, duration: 100)
        XCTAssertEqual(PlaybackProgressStore(defaults: defaults).resumePosition(bvid: "BV", cid: 1), 20)
        XCTAssertEqual(PlaybackProgressStore(defaults: defaults, storageNamespace: "offline").resumePosition(bvid: "BV", cid: 1), 70)
    }
}

private actor CacheTestAccount {
    var value: String? = "initial"
    func change(_ value: String?) { self.value = value }
}

actor CacheTestTransport: OfflineCacheTransport {
    struct Request: Sendable { let token: String; let cellular: Bool; let resumeData: Data? }
    nonisolated let events: AsyncStream<OfflineTransferEvent>
    private let continuation: AsyncStream<OfflineTransferEvent>.Continuation
    private(set) var requests: [Request] = []
    private var running: Set<String> = []
    init() {
        let stream = AsyncStream<OfflineTransferEvent>.makeStream()
        events = stream.stream; continuation = stream.continuation
    }
    func existingTokens() -> Set<String> { running }
    func start(token: String, url: URL, cellular: Bool, resumeData: Data?) {
        requests.append(.init(token: token, cellular: cellular, resumeData: resumeData)); running.insert(token)
    }
    func pause(token: String) -> Data? { running.remove(token); return Data("resume".utf8) }
    func cancel(token: String) { running.remove(token) }
    func network(available: Bool = true, cellular: Bool = false) { continuation.yield(.network(available: available, cellular: cellular)) }
    func failure(_ token: String, resumeData: Data? = nil) {
        running.remove(token)
        continuation.yield(.failed(token, "Transfer interrupted", resumeData, false))
    }
    func count() -> Int { requests.count }
    func finish(kind: String, data: Data) throws {
        guard let key = running.first(where: { $0.hasSuffix("/" + kind) }) else { throw OfflineCacheError.missingFile }
        try finish(token: key, data: data)
    }
    func finish(token: String, data: Data) throws {
        running.remove(token)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        continuation.yield(.downloaded(token, url, 200, Int64(data.count)))
    }
}
