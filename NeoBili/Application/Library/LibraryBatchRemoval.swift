import Foundation

/// One undo window per batch; completed writes are never rolled back locally.
@MainActor
enum LibraryBatchRemoval {
    static func perform<ID: Hashable & Sendable>(
        ids: [ID], isCurrent: @MainActor () -> Bool,
        confirm: @MainActor () async -> Bool, remove: @MainActor (ID) async throws -> Void
    ) async -> (succeeded: Set<ID>, error: String?) {
        var succeeded: Set<ID> = []
        var failure: String?
        guard isCurrent(), !Task.isCancelled, await confirm() else { return (succeeded, nil) }
        for id in ids {
            guard isCurrent(), !Task.isCancelled else { break }
            do { try await remove(id); succeeded.insert(id) }
            catch { if !error.isCancellation { failure = error.localizedDescription } }
        }
        return (succeeded, failure)
    }
}
