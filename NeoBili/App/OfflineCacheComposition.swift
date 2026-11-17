import Foundation
import NeoBiliData

enum OfflineCacheComposition {
    static let repository = OfflineCacheRepository.live(client: .shared, identity: .shared) { identifier in
        await OfflineBackgroundEvents.shared.finish(identifier)
    }
}

@MainActor
final class OfflineBackgroundEvents {
    static let shared = OfflineBackgroundEvents()
    private var handlers: [String: () -> Void] = [:]
    func register(_ identifier: String, completion: @escaping () -> Void) {
        handlers[identifier] = completion
        Task { await OfflineCacheComposition.repository.start() }
    }
    func finish(_ identifier: String) { handlers.removeValue(forKey: identifier)?() }
}

extension OfflineCacheStore {
    @MainActor static let shared = OfflineCacheStore(service: OfflineCacheComposition.repository.service)
}
