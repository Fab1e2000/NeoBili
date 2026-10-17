import SwiftUI

extension EnvironmentValues {
    /// A hierarchy may replace services without changing other windows or tests.
    @Entry private var injectedPlayerChromePreferences: PlayerChromePreferences?
    @MainActor var playerChromePreferences: PlayerChromePreferences {
        get { injectedPlayerChromePreferences ?? .shared }
        set { injectedPlayerChromePreferences = newValue }
    }
    @Entry var videoPreparation: VideoPreparationCache = ApplicationServices.playbackPreparation
    @Entry var applicationServices: ApplicationServices = .live
}
