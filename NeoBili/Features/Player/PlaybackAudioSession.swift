import AVFAudio
import Foundation

/// Audio focus belongs to audible playback, never application launch or a silent preview.
@MainActor
final class PlaybackAudioSession {
    typealias Completion = @MainActor @Sendable (Bool) -> Void

    @MainActor struct Endpoint {
        var configure: () throws -> Void
        var activate: (@escaping Completion) -> Void
        var deactivate: (@escaping Completion) -> Void

        static var live: Self {
            // Regression must not change the host's real audio session.
            if RuntimePolicy.isRegression {
                return Self(configure: {}, activate: { $0(true) }, deactivate: { $0(true) })
            }
            let session = AVAudioSession.sharedInstance()
            return Self(configure: {
                try session.setCategory(.playback, mode: .moviePlayback)
            }, activate: { complete in
                #if compiler(>=6.4)
                if #available(iOS 27.0, *) {
                    session.activate(options: []) { success, _ in
                        Task { @MainActor in complete(success) }
                    }
                    return
                }
                #endif
                do { try session.setActive(true); complete(true) }
                catch { complete(false) }
            }, deactivate: { complete in
                #if compiler(>=6.4)
                if #available(iOS 27.0, *) {
                    session.deactivate(options: [.notifyOthersOnDeactivation]) { success, _ in
                        Task { @MainActor in complete(success) }
                    }
                    return
                }
                #endif
                do { try session.setActive(false, options: [.notifyOthersOnDeactivation]); complete(true) }
                catch { complete(false) }
            })
        }
    }

    static let shared = PlaybackAudioSession(endpoint: .live)
    private enum State { case inactive, activating, active, deactivating }
    private var state: State = .inactive
    private var owners: Set<UUID> = []
    private var deactivationRetries = 0
    private let endpoint: Endpoint

    init(endpoint: Endpoint) { self.endpoint = endpoint }

    func acquire(_ owner: UUID) {
        owners.insert(owner)
        reconcile()
    }

    func release(_ owner: UUID) {
        owners.remove(owner)
        // A later confirmed stop may retry a previously failed release, even if EOF
        // already removed this owner. Each release has at most one immediate retry.
        if case .deactivating = state {} else { deactivationRetries = 1 }
        reconcile()
    }

    private func reconcile() {
        switch state {
        case .inactive where !owners.isEmpty:
            do { try endpoint.configure() } catch { return }
            state = .activating
            endpoint.activate { [weak self] success in
                guard let self else { return }
                state = success ? .active : .inactive
                // A failed activation is retried by the next playback/first-frame request,
                // not recursively. A late successful activation must respect a prior pause.
                if success { reconcile() }
            }
        case .active where owners.isEmpty:
            state = .deactivating
            endpoint.deactivate { [weak self] success in
                guard let self else { return }
                state = success ? .inactive : .active
                if success { reconcile() }
                else if owners.isEmpty, deactivationRetries > 0 {
                    deactivationRetries -= 1
                    reconcile()
                }
            }
        default: break
        }
    }
}
