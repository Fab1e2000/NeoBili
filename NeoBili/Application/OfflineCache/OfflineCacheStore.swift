import Foundation
import Observation
import NeoBiliDomain

@MainActor @Observable
final class OfflineCacheStore {
    private(set) var completed: [OfflineCacheEntry] = []
    private(set) var tasks: [OfflineCacheEntry] = []
    private(set) var taskCount = 0
    private(set) var completedCovers: [UUID: URL] = [:]
    private(set) var taskCovers: [UUID: URL] = [:]
    private(set) var speeds: [String: Double] = [:]
    private(set) var storageError: String?
    private(set) var availableBytes: Int64 = 0
    private var coverURLs: [UUID: URL] = [:]

    var snapshot: OfflineCacheSnapshot {
        get {
            var value = OfflineCacheSnapshot()
            value.completed = completed
            value.tasks = tasks
            value.coverURLs = coverURLs
            value.speeds = speeds
            value.error = storageError
            value.availableBytes = availableBytes
            return value
        }
        set { apply(newValue) }
    }

    private func apply(_ snapshot: OfflineCacheSnapshot) {
        let libraryChanged = completed != snapshot.completed
        if libraryChanged { completed = snapshot.completed }
        if tasks != snapshot.tasks { tasks = snapshot.tasks }
        if taskCount != snapshot.tasks.count { taskCount = snapshot.tasks.count }
        if speeds != snapshot.speeds { speeds = snapshot.speeds }
        if storageError != snapshot.error { storageError = snapshot.error }
        if availableBytes != snapshot.availableBytes { availableBytes = snapshot.availableBytes }
        let coversChanged = coverURLs != snapshot.coverURLs
        if coversChanged { coverURLs = snapshot.coverURLs }
        guard libraryChanged || coversChanged else { return }
        let completedGenerations = Set(snapshot.completed.map(\.generation))
        let libraryCovers = snapshot.coverURLs.filter { completedGenerations.contains($0.key) }
        let pendingCovers = snapshot.coverURLs.filter { libraryCovers[$0.key] == nil }
        if completedCovers != libraryCovers { completedCovers = libraryCovers }
        if taskCovers != pendingCovers { taskCovers = pendingCovers }
    }
    var errorMessage: String?
    let service: OfflineCacheService
    @ObservationIgnored private var observation: Task<Void, Never>?

    init(service: OfflineCacheService) { self.service = service }
    deinit { observation?.cancel() }

    func connect() {
        guard observation == nil else { return }
        observation = Task { [weak self, service] in
            for await snapshot in await service.updates() {
                guard !Task.isCancelled else { return }
                self?.apply(snapshot)
            }
        }
    }

    func perform(_ operation: @escaping @Sendable () async throws -> Void) {
        Task {
            do { try await operation() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func entries(in group: String) -> [OfflineCacheEntry] {
        completed.filter { $0.video.groupID == group }.sorted { $0.video.order < $1.video.order }
    }
}
