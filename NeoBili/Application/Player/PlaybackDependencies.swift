import Foundation

/// One playback graph is passed through the persistent media owner to its children.
@MainActor
struct PlaybackDependencies {
    let watchReports = PlaybackWatchReportSender.Registry()
    let watchProgress = PlaybackWatchProgressSender.Registry()
    let services: ApplicationServices
    let preparation: VideoPreparationCache
    let progress: PlaybackProgressStore
    let likes: VideoLikeStore
    let systemMedia: any SystemMediaControlling
}
