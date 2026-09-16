import Observation
import UIKit

/// Icon changes are serialized because UIKit rejects overlapping requests.
@MainActor
@Observable
final class ThemeIconController {
    private(set) var errorMessage: String?
    private var requestedIconName: String?
    private var isUpdating = false

    func apply(themeID: String) async {
        let theme = AppTheme.selected(themeID)
        requestedIconName = theme.id == AppTheme.defaultID ? nil : "NeoBiliIcon-\(theme.id)"
        guard !isUpdating else { return }
        let application = UIApplication.shared
        guard application.supportsAlternateIcons else {
            errorMessage = "当前系统不支持切换桌面图标。"
            return
        }
        isUpdating = true
        defer { isUpdating = false }
        errorMessage = nil

        while application.alternateIconName != requestedIconName {
            let target = requestedIconName
            do {
                // Once submitted, let UIKit finish even if the theme changes again.
                try await application.setAlternateIconName(target)
            } catch {
                // A newer selection should still get its own attempt.
                if target != requestedIconName { continue }
                errorMessage = "桌面图标未能更新，可点击下方重试。"
                return
            }
        }
    }
}
