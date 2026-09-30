import Foundation

// Only the network boundary is stubbed; the metadata store and dimensions are
// compiled directly from production source, including persistence and queues.
struct VideoDetail: Sendable {
    let dimension: VideoDimension?
    let duration: Int
}
actor VideoPreparationCache {
    static let shared = VideoPreparationCache()
    func detail(for bvid: String) async throws -> VideoDetail { throw URLError(.unsupportedURL) }
}

private final class MetadataRecordingDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var writes = 0
    private var bytes = 0
    private var mainThreadWrites = 0
    var counts: (writes: Int, bytes: Int, main: Int) {
        lock.lock(); defer { lock.unlock() }
        return (writes, bytes, mainThreadWrites)
    }
    override func set(_ value: Any?, forKey defaultName: String) {
        if let data = value as? Data {
            lock.lock()
            writes += 1; bytes += data.count
            if Thread.isMainThread { mainThreadWrites += 1 }
            lock.unlock()
        }
        super.set(value, forKey: defaultName)
    }
    func reset() {
        lock.lock(); defer { lock.unlock() }
        writes = 0; bytes = 0; mainThreadWrites = 0
    }
}

@MainActor @main
struct MetadataPersistenceRegression {
    private struct Entry: Codable {
        let portrait: Bool?
        let durationSeconds: Int?
        let durationChecked: Bool?
        let expiresAt: Date
    }
    static func main() async throws {
        let baseline = CommandLine.arguments.contains("--baseline")
        let suite = "neobili.metadata.persistence.\(UUID())"
        let defaults = MetadataRecordingDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 1_000_000)
        let seed = Dictionary(uniqueKeysWithValues: (1...1_980).map {
            ("old\($0)", Entry(portrait: false, durationSeconds: 100,
                             durationChecked: true, expiresAt: now.addingTimeInterval(86_400)))
        })
        defaults.set(try JSONEncoder().encode(seed), forKey: "neobili.portraitVideoCache.v1")
        defaults.reset()
        var calls = 0
        let store = PortraitVideoStore(defaults: defaults, now: { now }, metadataLoader: { _ in
            calls += 1
            return PortraitVideoStore.Metadata(dimension: VideoDimension(width: 1920, height: 1080),
                                                durationSeconds: 200)
        })
        let ids = (1...20).map { "new\($0)" }
        let start = ContinuousClock.now
        await store.resolve(ids)
        let duration = start.duration(to: .now)
        let counts = defaults.counts
        precondition(calls == 20)
        precondition(counts.writes == (baseline ? 20 : 1), "A completed page must commit one snapshot")
        if !baseline { precondition(counts.main == 0, "Encoding and persistence must leave the main thread") }
        let data = defaults.data(forKey: "neobili.portraitVideoCache.v1")!
        let saved = try JSONDecoder().decode([String: Entry].self, from: data)
        precondition(saved.count == 2_000 && saved["old1"] != nil && saved["new20"]?.durationSeconds == 200)
        let restored = PortraitVideoStore(defaults: defaults, now: { now }, loader: { _ in
            preconditionFailure("Completed batch must survive reopening without another request")
        })
        await restored.resolve(ids)
        precondition(restored.isPortrait(bvid: "new1") == false)
        await store.resolve(ids)
        precondition(defaults.counts.writes == counts.writes, "Cache hits must not write snapshots")
        print("METADATA_PAGE_20 cached=1980 writes=\(counts.writes) encoded_bytes=\(counts.bytes) elapsed=\(duration)")

        // A cancelled page stops waiting immediately; an already active shared
        // result must still become durable after all its waiters have left.
        var held: CheckedContinuation<VideoDimension?, Never>?
        let cancelledStore = PortraitVideoStore(defaults: defaults, now: { now }) { _ in
            await withCheckedContinuation { held = $0 }
        }
        let task = Task { await cancelledStore.resolve(["late"]) }
        try await waitUntil { held != nil }
        task.cancel()
        await task.value
        held?.resume(returning: VideoDimension(width: 720, height: 1280))
        held = nil
        try await waitUntil {
            guard let data = defaults.data(forKey: "neobili.portraitVideoCache.v1"),
                  let entries = try? JSONDecoder().decode([String: Entry].self, from: data) else { return false }
            return entries["late"]?.portrait == true && entries.count <= 2_000
        }
        print("PASS Metadata persistence: batching, background writes, cache hits, restart, capacity, cancelled waiter")
    }
    static func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !predicate() {
            precondition(ContinuousClock.now < deadline, "Timed out awaiting metadata persistence")
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
