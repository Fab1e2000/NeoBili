import SwiftUI

/// Only this leaf reads observable playback progress. Menu content is outside
/// its Observation dependency scope, so normal playback ticks cannot refresh it.
struct PlayerTimeline: View {
    @State private var storyboardStore = VideoStoryboardStore()
    let progressSource: PlayerProgressSource
    let isLive: Bool
    let isWaiting: Bool
    let canControlPlayback: Bool
    let showsTimeLabels: Bool
    let isMinimal: Bool
    let onScrub: (Double) -> Void
    let onScrubEnd: (Double) -> Void

    var body: some View {
        if isLive {
            HStack(spacing: 6) {
                Circle().fill(isWaiting ? Color.white.opacity(0.6) : .red).frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(isWaiting ? (isMinimal ? "连接" : "连接中") : (isMinimal ? "直播" : "直播中"))
                    .font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, isMinimal ? 6 : 12)
            .frame(height: 32)
            .playerGlassSurface(in: Capsule())
            .frame(height: 48)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(isWaiting ? "正在连接直播" : "直播中")
            .accessibilityIdentifier("player.liveStatus")
        } else {
            let progress = progressSource.read()
            HStack(spacing: showsTimeLabels ? 8 : 0) {
                if showsTimeLabels {
                    Text(PlaybackTime.text(progress.position)).lineLimit(1).minimumScaleFactor(0.7).accessibilityHidden(true)
                }
                VideoScrubber(position: progress.position, buffered: progress.buffered, duration: progress.duration,
                              onScrub: onScrub, onScrubEnd: onScrubEnd, previewVideo: progress.previewVideo)
                    .disabled(!canControlPlayback || progress.duration <= 0)
                    .frame(minWidth: 44)
                if showsTimeLabels {
                    Text(PlaybackTime.text(progress.duration))
                        .foregroundStyle(.white.opacity(0.8)).accessibilityHidden(true)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .font(.caption.monospacedDigit().weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, showsTimeLabels ? 12 : 6)
            .frame(height: 32)
            .playerGlassSurface(in: Capsule())
            .frame(height: 48)
            .overlayPreferenceValue(VideoScrubPreviewPreference.self) { preview in
                GeometryReader { geometry in
                    if let preview {
                        let bounds = geometry[preview.bounds]
                        let width = min(CGFloat(144), geometry.size.width)
                        let focus = bounds.minX + bounds.width * preview.seconds / preview.duration
                        VideoSeekPreview(video: preview.video, seconds: preview.seconds, store: progress.previewStore ?? storyboardStore)
                            .frame(width: width, height: 104)
                            .position(x: min(max(focus, width / 2), geometry.size.width - width / 2),
                                      y: bounds.minY - 62)
                    }
                }
                .allowsHitTesting(false)
            }
            .accessibilityIdentifier("player.timeline")
        }
    }
}
