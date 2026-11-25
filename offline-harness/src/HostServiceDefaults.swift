import Foundation
import NeoBiliDomain

/// Scenarios that inject their own loaders have no configured transport.
extension ApplicationServices {
    static let live = ApplicationServices(session: .init(
        currentID: { HostSession.id }, homeAccount: { .init(accountID: nil, hasAppCredential: false) }
    ))
}

private enum HostSession {
    static let id = UUID()
}
