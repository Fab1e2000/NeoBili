import Foundation

/// Coalesce image work while tracking its consumers. A reused cell can leave
/// immediately; the transfer/decode is cancelled only after its last consumer
/// leaves. Generation IDs prevent a late cancelled operation from touching a
/// replacement request for the same URL.
actor ImageRequestPool<Key: Hashable & Sendable, Value: Sendable> {
    private struct Entry {
        let generation: UUID
        let task: Task<Void, Never>
        var consumers: [UUID: CheckedContinuation<Value, Error>]
    }
    private var entries: [Key: Entry] = [:]
    var consumerCount: Int { entries.values.reduce(0) { $0 + $1.consumers.count } }

    func value(for key: Key, operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        let consumer = UUID()
        let value: Value = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if entries[key] != nil {
                    entries[key]?.consumers[consumer] = continuation
                    return
                }
                let generation = UUID()
                let task = Task {
                    let result: Result<Value, Error>
                    do {
                        try Task.checkCancellation()
                        let value = try await operation()
                        try Task.checkCancellation()
                        result = .success(value)
                    } catch {
                        result = .failure(error)
                    }
                    complete(key, generation: generation, result: result)
                }
                entries[key] = Entry(generation: generation, task: task, consumers: [consumer: continuation])
            }
        } onCancel: {
            Task { await self.cancel(key, consumer: consumer) }
        }
        try Task.checkCancellation()
        return value
    }

    private func cancel(_ key: Key, consumer: UUID) {
        guard let continuation = entries[key]?.consumers.removeValue(forKey: consumer) else { return }
        continuation.resume(throwing: CancellationError())
        if entries[key]?.consumers.isEmpty == true {
            entries.removeValue(forKey: key)?.task.cancel()
        }
    }

    private func complete(_ key: Key, generation: UUID, result: Result<Value, Error>) {
        guard entries[key]?.generation == generation,
              let entry = entries.removeValue(forKey: key) else { return }
        for continuation in entry.consumers.values { continuation.resume(with: result) }
    }
}

/// Limit CPU-heavy ImageIO work without retaining cancelled offscreen images
/// (and their compressed data) behind the active decodes.
actor ImageDecodeGate {
    static let shared = ImageDecodeGate(limit: 4)
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }
    private let limit: Int
    private var active = 0
    private var waiters: [Waiter] = []
    var queuedCount: Int { waiters.count }

    init(limit: Int) { self.limit = max(1, limit) }

    func enter() async throws {
        try Task.checkCancellation()
        if active < limit {
            active += 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func leave() {
        if waiters.isEmpty {
            active -= 1
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }

    private func cancel(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
