import Foundation

/// Shared by consumers of one in-flight request and read by the decode queue.
public final class ImageWorkPriority: @unchecked Sendable {
    private let lock = NSLock()
    private var visible: Bool

    fileprivate init(isVisible: Bool) { visible = isVisible }
    public var isVisible: Bool { lock.withLock { visible } }
    fileprivate func promote() { lock.withLock { visible = true } }
}

/// Coalesce image work while tracking its consumers. A reused cell can leave
/// immediately; the transfer/decode is cancelled only after its last consumer
/// leaves. Generation IDs prevent a late cancelled operation from touching a
/// replacement request for the same URL.
public actor ImageRequestPool<Key: Hashable & Sendable, Value: Sendable> {
    private struct Entry {
        let generation: UUID
        let priority: ImageWorkPriority
        let task: Task<Void, Never>
        var consumers: [UUID: CheckedContinuation<Value, Error>]
    }
    public init() {}

    private var entries: [Key: Entry] = [:]
    public var consumerCount: Int { entries.values.reduce(0) { $0 + $1.consumers.count } }

    public func value(for key: Key, operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try await value(for: key, prefetch: false) { _ in try await operation() }
    }

    public func value(for key: Key, prefetch: Bool,
                      operation: @escaping @Sendable (ImageWorkPriority) async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        let consumer = UUID()
        let value: Value = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if let priority = entries[key]?.priority {
                    if !prefetch { priority.promote() }
                    entries[key]?.consumers[consumer] = continuation
                    return
                }
                let generation = UUID()
                let priority = ImageWorkPriority(isVisible: !prefetch)
                let task = Task {
                    let result: Result<Value, Error>
                    do {
                        try Task.checkCancellation()
                        let value = try await operation(priority)
                        try Task.checkCancellation()
                        result = .success(value)
                    } catch {
                        result = .failure(error)
                    }
                    complete(key, generation: generation, result: result)
                }
                entries[key] = Entry(generation: generation, priority: priority, task: task, consumers: [consumer: continuation])
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
public actor ImageDecodeGate {
    private struct Waiter {
        let id: UUID
        let priority: ImageWorkPriority?
        let continuation: CheckedContinuation<Void, Error>
    }
    private let limit: Int
    private var active = 0
    private var waiters: [Waiter] = []
    var queuedCount: Int { waiters.count }

    public init(limit: Int) { self.limit = max(1, limit) }

    public func enter(priority: ImageWorkPriority? = nil) async throws {
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
                    waiters.append(Waiter(id: id, priority: priority, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    public func leave() {
        if waiters.isEmpty {
            active -= 1
        } else {
            let next = waiters.firstIndex { $0.priority?.isVisible ?? true } ?? waiters.startIndex
            waiters.remove(at: next).continuation.resume()
        }
    }

    private func cancel(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
