import Foundation
import Synchronization

/// One byte-bounded bitmap store for synchronous UI reads and asynchronous
/// loaders. The lock only covers dictionary bookkeeping, never decode or I/O.
final class ImageMemoryCache<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    private struct Entry {
        let value: Value
        let cost: Int
        var lastAccess: UInt64
    }
    private struct State {
        var entries: [Key: Entry] = [:]
        var bytes = 0
        var sequence: UInt64 = 0
    }
    private let state = Mutex(State())
    private let maximumBytes: Int
    private let maximumEntries: Int

    init(maximumBytes: Int, maximumEntries: Int) {
        self.maximumBytes = max(0, maximumBytes)
        self.maximumEntries = max(1, maximumEntries)
    }

    var cachedByteCount: Int { state.withLock { $0.bytes } }

    func value(for key: Key) -> Value? {
        state.withLock { state in
            guard var entry = state.entries[key] else { return nil }
            state.sequence &+= 1
            entry.lastAccess = state.sequence
            state.entries[key] = entry
            return entry.value
        }
    }

    func insert(_ value: Value, for key: Key, cost: Int) {
        guard cost >= 0, cost <= maximumBytes else { return }
        state.withLock { state in
            if let replaced = state.entries.removeValue(forKey: key) { state.bytes -= replaced.cost }
            while state.bytes > maximumBytes - cost || state.entries.count >= maximumEntries {
                guard let oldest = state.entries.min(by: { $0.value.lastAccess < $1.value.lastAccess }) else { break }
                state.bytes -= oldest.value.cost
                state.entries[oldest.key] = nil
            }
            state.sequence &+= 1
            state.entries[key] = Entry(value: value, cost: cost, lastAccess: state.sequence)
            state.bytes += cost
        }
    }

    func removeAll() {
        state.withLock { state in
            state.entries.removeAll()
            state.bytes = 0
        }
    }
}
