import UIKit

extension ThemeIconController.IconEndpoint {
    /// 生产端点：UIKit 的备选图标接口。
    @MainActor static let uiKit = ThemeIconController.IconEndpoint(
        supportsAlternateIcons: { UIApplication.shared.supportsAlternateIcons },
        reportedIconName: { UIApplication.shared.alternateIconName },
        setAlternateIconName: { name in try await UIApplication.shared.setAlternateIconName(name) }
    )
}
