import Foundation

@main
struct ImagePipelineRegression {
    static func main() async throws {
        try await sharedConsumers()
        try await cancelledDecodeQueue()
        try await lateCancelledCompletion()
        try await cancelledBeforeRequest()
        boundedMemory()
        print("ALL IMAGE PIPELINE CHECKS PASS")
    }

    static func sharedConsumers() async throws {
        let pool = ImageRequestPool<String, Int>()
        let probe = SuspendedImages()
        let first = Task { try await pool.value(for: "cover") { await probe.load("cover") } }
        try await until { await pool.consumerCount == 1 }
        let second = Task { try await pool.value(for: "cover") { await probe.load("duplicate") } }
        try await until { await pool.consumerCount == 2 }
        first.cancel()
        do { _ = try await first.value; preconditionFailure("Cancelled consumer must leave immediately") }
        catch is CancellationError { }
        try await until { await pool.consumerCount == 1 }
        await probe.release("cover", value: 42)
        let value = try await second.value
        precondition(value == 42)
        let starts = await probe.starts
        precondition(starts == ["cover"], "A visible consumer must retain the one shared operation")
        print("PASS  One cancelled consumer exits while the second shares the original transfer")
    }

    static func cancelledDecodeQueue() async throws {
        let pool = ImageRequestPool<Int, Int>()
        let gate = ImageDecodeGate(limit: 1)
        let probe = DecodeProbe()
        try await gate.enter() // Keep the only slot busy, as a real ImageIO decode would.
        let queued = (0..<100).map { id in
            Task {
                try await pool.value(for: id) {
                    try await gate.enter()
                    await probe.decoded()
                    await gate.leave()
                    return id
                }
            }
        }
        try await until { await gate.queuedCount == 100 }
        let start = ContinuousClock.now
        queued.forEach { $0.cancel() }
        for task in queued {
            do { _ = try await task.value; preconditionFailure("Offscreen work must cancel") }
            catch is CancellationError { }
        }
        try await until { await gate.queuedCount == 0 }
        let elapsed = start.duration(to: .now)
        let decoded = await probe.count
        precondition(decoded == 0, "Cancelled queued images must never enter ImageIO")
        await gate.leave()
        // Verify cancellations did not consume a slot or corrupt the permit count.
        try await gate.enter()
        await gate.leave()
        print("PASS  100 offscreen requests release queued decode work before active decode finishes (\(elapsed))")
    }

    static func lateCancelledCompletion() async throws {
        let pool = ImageRequestPool<String, Int>()
        let probe = SuspendedImages()
        let old = Task { try await pool.value(for: "same-url") { await probe.load("old") } }
        try await until { await probe.starts == ["old"] }
        old.cancel()
        _ = try? await old.value
        let replacement = Task { try await pool.value(for: "same-url") { await probe.load("replacement") } }
        try await until { await probe.starts == ["old", "replacement"] }
        // This deliberately ignores cancellation, like a synchronous ImageIO call.
        await probe.release("old", value: 1)
        try await until { await probe.finished.contains("old") }
        for _ in 0..<20 { await Task.yield() }
        let joined = Task { try await pool.value(for: "same-url") { await probe.load("unexpected-third") } }
        try await until { await pool.consumerCount == 2 }
        await probe.release("replacement", value: 2)
        let values = try await (replacement.value, joined.value)
        precondition(values == (2, 2))
        let starts = await probe.starts
        precondition(starts == ["old", "replacement"], "Old completion cannot remove the replacement")
        print("PASS  Late cancelled completion cannot remove or satisfy a new request for the same URL")
    }

    static func cancelledBeforeRequest() async throws {
        let pool = ImageRequestPool<String, Int>()
        let probe = DecodeProbe()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await pool.value(for: "cancelled") { await probe.decoded(); return 1 }
        }
        do { _ = try await task.value; preconditionFailure("An already-cancelled caller must fail") }
        catch is CancellationError { }
        let count = await probe.count
        precondition(count == 0)
        print("PASS  Already-cancelled caller never starts network/decode work")
    }

    static func boundedMemory() {
        let cache = ImageMemoryCache<String, Bitmap>(maximumBytes: 128, maximumEntries: 3)
        weak var old: Bitmap?
        do {
            let bitmap = Bitmap()
            old = bitmap
            cache.insert(bitmap, for: "old", cost: 64)
        }
        cache.insert(Bitmap(), for: "hot", cost: 64)
        _ = cache.value(for: "hot")
        cache.insert(Bitmap(), for: "new", cost: 64)
        precondition(old == nil, "Eviction must release the only cache owner")
        precondition(cache.cachedByteCount == 128 && cache.value(for: "hot") != nil)
        cache.insert(Bitmap(), for: "hot", cost: 64)
        precondition(cache.cachedByteCount == 128, "Replacement must not double-charge")
        cache.insert(Bitmap(), for: "oversized", cost: 256)
        precondition(cache.cachedByteCount == 128 && cache.value(for: "hot") != nil)
        weak var retained: Bitmap?
        retained = cache.value(for: "hot")
        cache.removeAll()
        precondition(retained == nil && cache.cachedByteCount == 0)
        print("PASS  One cache owner, byte-bounded LRU, replacement, oversized rejection and full release")
    }

    static func until(_ condition: @Sendable () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        throw URLError(.timedOut)
    }
}

private final class Bitmap: Sendable { }
private actor DecodeProbe {
    private(set) var count = 0
    func decoded() { count += 1 }
}
private actor SuspendedImages {
    private var continuations: [String: CheckedContinuation<Int, Never>] = [:]
    private(set) var starts: [String] = []
    private(set) var finished = Set<String>()
    func load(_ name: String) async -> Int {
        starts.append(name)
        let value = await withCheckedContinuation { continuations[name] = $0 }
        finished.insert(name)
        return value
    }
    func release(_ name: String, value: Int) {
        continuations.removeValue(forKey: name)?.resume(returning: value)
    }
}
