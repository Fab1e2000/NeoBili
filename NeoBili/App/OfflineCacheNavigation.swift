import SwiftUI
import Observation

@MainActor @Observable
final class OfflineCacheNavigation {
    private(set) var requestID: UUID?

    func openDownloads() { requestID = UUID() }
}

extension EnvironmentValues {
    @Entry var offlineCacheNavigation: OfflineCacheNavigation? = nil
}
