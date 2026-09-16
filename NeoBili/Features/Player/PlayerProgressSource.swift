import SwiftUI

struct PlayerProgressSnapshot {
    let position: Double
    let duration: Double
    let buffered: Double
    var previewStore: VideoStoryboardStore? = nil
    var previewVideo: VideoPreviewID? = nil
}

/// Pass the read operation, not a periodically changing snapshot, through chrome.
/// SwiftUI observes the model only in the leaf body that invokes this closure.
struct PlayerProgressSource {
    let read: @MainActor () -> PlayerProgressSnapshot
}

struct PlayerProgressGestureLayer: View {
    let progressSource: PlayerProgressSource
    let isFullScreen: Bool
    var canSeek = true
    var feedbackTopInset: CGFloat = 0
    let onTap: () -> Void
    let onToggleFullScreen: () -> Void
    let onSeekChanged: (Double) -> Void
    let onSeekEnded: (Double) -> Void
    let onSeekCancelled: () -> Void

    var body: some View {
        let progress = progressSource.read()
        PlayerVerticalGestureLayer(
            isFullScreen: isFullScreen, currentTime: progress.position, duration: progress.duration, canSeek: canSeek,
            feedbackTopInset: feedbackTopInset,
            onTap: onTap, onToggleFullScreen: onToggleFullScreen,
            onSeekChanged: onSeekChanged, onSeekEnded: onSeekEnded, onSeekCancelled: onSeekCancelled
        )
        .task(id: progress.previewStore?.storyboard?.tile(at: progress.position)?.url) {
            // Warm the next sheet as normal playback moves between storyboards,
            // even while playback controls are hidden.
            await progress.previewStore?.prepare(at: progress.position)
        }
    }
}
