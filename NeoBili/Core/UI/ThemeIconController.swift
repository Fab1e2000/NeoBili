import Foundation
import Observation

/// Icon changes are serialized because UIKit rejects overlapping requests.
///
/// The system endpoints live behind ``IconEndpoint`` so the host-side
/// regression can drive this exact loop without UIKit; the production
/// endpoint is `ThemeIconController+UIKit.swift`.
@MainActor
@Observable
final class ThemeIconController {
    /// UIApplication's alternate-icon surface, closure-shaped for tests.
    struct IconEndpoint {
        var supportsAlternateIcons: @MainActor () -> Bool
        var reportedIconName: @MainActor () -> String?
        var setAlternateIconName: @MainActor (_ name: String?) async throws -> Void
    }

    private(set) var errorMessage: String?
    private var requestedIconName: String?
    private var isUpdating = false
    private let endpoint: IconEndpoint

    init(endpoint: IconEndpoint) {
        self.endpoint = endpoint
    }

    func apply(themeID: String) async {
        let theme = AppTheme.selected(themeID)
        requestedIconName = theme.id == AppTheme.defaultID ? nil : "NeoBiliIcon-\(theme.id)"
        guard !isUpdating else { return }
        guard endpoint.supportsAlternateIcons() else {
            errorMessage = "当前系统不支持切换桌面图标。"
            return
        }
        isUpdating = true
        defer { isUpdating = false }
        errorMessage = nil

        while endpoint.reportedIconName() != requestedIconName {
            let target = requestedIconName
            do {
                // Once submitted, let UIKit finish even if the theme changes again.
                try await endpoint.setAlternateIconName(target)
                // Completion means the request was accepted. The reported icon
                // name can lag behind an accepted change; polling it by
                // resubmitting the same request would spin forever and burn
                // CPU. Only a theme selected during this await needs another
                // request.
                if target == requestedIconName { return }
            } catch {
                // A newer selection should still get its own attempt.
                if target != requestedIconName { continue }
                errorMessage = "桌面图标未能更新，可点击下方重试。"
                return
            }
        }
    }
}
