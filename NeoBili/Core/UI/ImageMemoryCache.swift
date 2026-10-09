import Foundation
import Synchronization

/// One byte-bounded bitmap store for synchronous UI reads and asynchronous
/// loaders. Recency links keep hits and each eviction constant-time under the
/// lock; scrolling never scans every retained bitmap to choose a victim.
final class ImageMemoryCache<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    private struct Entry {
        let value: Value
        let cost: Int
        var older: Key?
        var newer: Key?
    }
    private struct State {
        var entries: [Key: Entry] = [:]
        var bytes = 0
        var oldest: Key?
        var newest: Key?

        mutating func unlink(_ key: Key, entry: Entry) {
            if let older = entry.older { entries[older]?.newer = entry.newer }
            else { oldest = entry.newer }
            if let newer = entry.newer { entries[newer]?.older = entry.older }
            else { newest = entry.older }
        }

        mutating func append(_ key: Key, entry: Entry) {
            var entry = entry
            entry.older = newest
            entry.newer = nil
            if let newest { entries[newest]?.newer = key }
            else { oldest = key }
            newest = key
            entries[key] = entry
        }

        mutating func remove(_ key: Key) {
            guard let entry = entries.removeValue(forKey: key) else { return }
            unlink(key, entry: entry)
            bytes -= entry.cost
        }
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
            guard let entry = state.entries[key] else { return nil }
            if state.newest != key {
                state.unlink(key, entry: entry)
                state.append(key, entry: entry)
            }
            return entry.value
        }
    }

    func insert(_ value: Value, for key: Key, cost: Int) {
        guard cost >= 0, cost <= maximumBytes else { return }
        state.withLock { state in
            state.remove(key)
            while state.bytes > maximumBytes - cost || state.entries.count >= maximumEntries {
                guard let oldest = state.oldest else { break }
                state.remove(oldest)
            }
            state.append(key, entry: Entry(value: value, cost: cost))
            state.bytes += cost
        }
    }

    func removeAll() {
        state.withLock { state in
            state = State()
        }
    }
}
