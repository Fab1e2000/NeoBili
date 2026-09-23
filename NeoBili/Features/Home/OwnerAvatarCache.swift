import Foundation

/// App recommendations omit avatars. Resolve by UP ID, coalesce duplicates and
/// keep at most two metadata requests active instead of fetching every video detail.
actor OwnerAvatarCache {
    static let shared = OwnerAvatarCache()
    private struct Entry {
        let url: URL?
        let expiresAt: Date
    }
    private var entries: [Int: Entry] = [:]
    private var inFlight: [Int: Task<URL?, Never>] = [:]
    private var lanes: [Task<URL?, Never>?] = [nil, nil]
    private var nextLane = 0
    private let loader: @Sendable (Int) async throws -> URL?

    init(loader: @escaping @Sendable (Int) async throws -> URL? = { mid in
        try await BiliAPI.spaceCard(mid: mid).secureAvatarURL
    }) { self.loader = loader }

    func url(for mid: Int) async -> URL? {
        guard mid > 0, !Task.isCancelled else { return nil }
        if let entry = entries[mid], entry.expiresAt > Date() { return entry.url }
        if let task = inFlight[mid] { return await task.value }
        let previous = lanes[nextLane]
        let loader = loader
        let task = Task {
            _ = await previous?.value
            return try? await loader(mid)
        }
        lanes[nextLane] = task
        nextLane = (nextLane + 1) % lanes.count
        inFlight[mid] = task
        let result = await task.value
        inFlight[mid] = nil
        if entries.count >= 256, let oldest = entries.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
            entries[oldest] = nil
        }
        entries[mid] = Entry(url: result, expiresAt: Date().addingTimeInterval(result == nil ? 15 : 3_600))
        return result
    }
}
