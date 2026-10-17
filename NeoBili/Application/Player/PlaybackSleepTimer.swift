import Foundation
import Observation

/// Owns the one-shot wait and observable menu selection for a playback session.
@MainActor @Observable
final class PlaybackSleepTimer {
    enum Option: Equatable, Hashable {
        case minutes(Int)
        case afterVideoEnd
    }

    static let options: [Option] = [
        .minutes(15), .minutes(30), .minutes(60), .minutes(90), .minutes(120)
    ]

    private(set) var deadline: Date?
    private(set) var afterVideoEnd = false
    private(set) var selectedOption: Option?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let waiter: @Sendable (TimeInterval) async throws -> Void

    init(waiter: @escaping @Sendable (TimeInterval) async throws -> Void) {
        self.waiter = waiter
    }

    deinit { task?.cancel() }

    var isActive: Bool { deadline != nil || afterVideoEnd }

    func set(_ option: Option, onExpiry: @escaping @MainActor () -> Void) {
        cancel()
        selectedOption = option
        switch option {
        case .minutes(let minutes):
            deadline = Date.now.addingTimeInterval(TimeInterval(minutes) * 60)
            let waiter = waiter
            task = Task {
                try? await waiter(TimeInterval(minutes) * 60)
                guard !Task.isCancelled else { return }
                onExpiry()
            }
        case .afterVideoEnd:
            afterVideoEnd = true
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        deadline = nil
        afterVideoEnd = false
        selectedOption = nil
    }
}
