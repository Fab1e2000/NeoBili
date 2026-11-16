import Foundation

public struct OfflineCacheService: Sendable {
    public var updates: @Sendable () async -> AsyncStream<OfflineCacheSnapshot>
    public var enqueue: @Sendable ([OfflineVideo], Int, Int, Bool) async throws -> Void
    public var pause: @Sendable (String) async throws -> Void
    public var resume: @Sendable (String, Bool) async throws -> Void
    public var cancel: @Sendable (String) async throws -> Void
    public var delete: @Sendable ([String]) async throws -> Void
    public var playback: @Sendable (String) async throws -> OfflinePlaybackDescriptor
    public var releasePlayback: @Sendable (UUID) async -> Void

    public init(
        updates: @escaping @Sendable () async -> AsyncStream<OfflineCacheSnapshot> = { AsyncStream { $0.finish() } },
        enqueue: @escaping @Sendable ([OfflineVideo], Int, Int, Bool) async throws -> Void = { _, _, _, _ in throw OfflineCacheError.unconfigured },
        pause: @escaping @Sendable (String) async throws -> Void = { _ in throw OfflineCacheError.unconfigured },
        resume: @escaping @Sendable (String, Bool) async throws -> Void = { _, _ in throw OfflineCacheError.unconfigured },
        cancel: @escaping @Sendable (String) async throws -> Void = { _ in throw OfflineCacheError.unconfigured },
        delete: @escaping @Sendable ([String]) async throws -> Void = { _ in throw OfflineCacheError.unconfigured },
        playback: @escaping @Sendable (String) async throws -> OfflinePlaybackDescriptor = { _ in throw OfflineCacheError.unconfigured },
        releasePlayback: @escaping @Sendable (UUID) async -> Void = { _ in }
    ) {
        self.updates = updates; self.enqueue = enqueue; self.pause = pause; self.resume = resume
        self.cancel = cancel; self.delete = delete; self.playback = playback; self.releasePlayback = releasePlayback
    }
}
