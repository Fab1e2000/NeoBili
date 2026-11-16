import Foundation
import Observation
import NeoBiliDomain

@MainActor @Observable
final class OfflineCacheStore {
    var snapshot = OfflineCacheSnapshot()
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
                self?.snapshot = snapshot
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
        snapshot.completed.filter { $0.video.groupID == group }.sorted { $0.video.order < $1.video.order }
    }
}
