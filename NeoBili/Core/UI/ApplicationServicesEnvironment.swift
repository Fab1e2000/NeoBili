import SwiftUI

extension EnvironmentValues {
    @Entry var imagePipeline: BiliImagePipeline = .live
    @Entry private var injectedCommentEmoteStore: CommentEmoteStore?
    @MainActor var commentEmoteStore: CommentEmoteStore {
        get { injectedCommentEmoteStore ?? .shared }
        set { injectedCommentEmoteStore = newValue }
    }
    /// A hierarchy may replace services without changing other windows or tests.
    @Entry private var injectedPlayerChromePreferences: PlayerChromePreferences?
    @MainActor var playerChromePreferences: PlayerChromePreferences {
        get { injectedPlayerChromePreferences ?? .shared }
        set { injectedPlayerChromePreferences = newValue }
    }
    @Entry var videoPreparation: VideoPreparationCache = ApplicationServices.playbackPreparation
    @Entry var applicationServices: ApplicationServices = .live
}
