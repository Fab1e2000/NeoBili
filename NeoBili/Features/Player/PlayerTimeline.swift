import NeoBiliDomain
import SwiftUI

/// Within the chrome, only this leaf observes playback progress.
struct PlayerTimeline: View {
    @State private var storyboardStore = VideoStoryboardStore()
    @State private var showsChapterMenuWhileEditing: Bool?
    let progressSource: PlayerProgressSource
    let isLive: Bool
    let isWaiting: Bool
    let canControlPlayback: Bool
    let showsTimeLabels: Bool
    let isMinimal: Bool
    let width: CGFloat
    let isFullScreen: Bool
    let onScrub: (Double) -> Void
    let onScrubEnd: (Double) -> Void
    let onMenuInteraction: () -> Void

    private static func chapterMenuWidth(in width: CGFloat, isFullScreen: Bool) -> CGFloat {
        min(width * (isFullScreen ? 0.23 : 0.32), isFullScreen ? 172 : 116)
    }

    var body: some View {
        if isLive {
            HStack(spacing: 6) {
                Circle().fill(isWaiting ? Color.white.opacity(0.6) : .red).frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(isWaiting ? (isMinimal ? "连接" : "连接中") : (isMinimal ? "直播" : "直播中"))
                    .font(.app(.caption, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
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
            HStack(spacing: 6) {
                if showsChapterMenuWhileEditing ?? !progress.chapters.isEmpty {
                    chapterMenu(progress.chapters, position: progress.position, duration: progress.duration)
                }
                scrubber(progress)
            }
            .overlayPreferenceValue(VideoScrubPreviewPreference.self) { preview in
                GeometryReader { geometry in
                    if let preview {
                        let chapter = progress.chapters.chapter(at: preview.seconds)
                        let bounds = geometry[preview.bounds]
                        let width = min(CGFloat(144), geometry.size.width)
                        let focus = bounds.minX + bounds.width * preview.seconds / preview.duration
                        Color.clear.frame(width: width, height: 0)
                            .overlay(alignment: .bottom) {
                                VideoSeekPreview(video: preview.video, seconds: preview.seconds,
                                                 store: progress.previewStore ?? storyboardStore, chapter: chapter)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .position(x: min(max(focus, width / 2), geometry.size.width - width / 2),
                                      y: bounds.minY - 10)
                    }
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func scrubber(_ progress: PlayerProgressSnapshot) -> some View {
        HStack(spacing: showsTimeLabels ? 8 : 0) {
            if showsTimeLabels {
                Text(PlaybackTime.text(progress.position)).lineLimit(1).minimumScaleFactor(0.7).accessibilityHidden(true)
            }
            VideoScrubber(position: progress.position, buffered: progress.buffered, duration: progress.duration,
                          onScrub: onScrub, onScrubEnd: onScrubEnd, previewVideo: progress.previewVideo,
                          chapters: progress.chapters, onEditingChanged: { editing in
                              // Preserve the track's position and width until the native drag ends.
                              showsChapterMenuWhileEditing = editing ? !progress.chapters.isEmpty : nil
                          })
                .disabled(!canControlPlayback || progress.duration <= 0)
                .frame(minWidth: 44)
            if showsTimeLabels {
                Text(PlaybackTime.text(progress.duration))
                    .foregroundStyle(.white.opacity(0.8)).accessibilityHidden(true)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .font(.app(.caption, weight: .semibold)).monospacedDigit()
        .foregroundStyle(.white)
        .padding(.horizontal, showsTimeLabels ? 12 : 6)
        .frame(height: 32)
        .playerGlassSurface(in: Capsule())
        .frame(height: 48)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player.timeline")
    }

    private func chapterMenu(_ chapters: [VideoChapter], position: Double, duration: Double) -> some View {
        let hasKnownDuration = duration.isFinite && duration > 0
        func canJump(to chapter: VideoChapter) -> Bool { !hasKnownDuration || chapter.from < duration }
        let current = chapters.chapter(at: position).flatMap { canJump(to: $0) ? $0 : nil }
        let title = current?.title ?? String(localized: "章节")
        let menuWidth = Self.chapterMenuWidth(in: width, isFullScreen: isFullScreen)
        let isEnabled = canControlPlayback && !chapters.isEmpty
        return ZStack {
            Menu {
                ForEach(chapters) { chapter in
                    Button {
                        onScrubEnd(chapter.from)
                    } label: {
                        let label = "\(PlaybackTime.text(chapter.from, minimumMinuteDigits: 2)) \(chapter.title)"
                        if chapter == current { Label(label, systemImage: "checkmark") }
                        else { Text(label) }
                    }
                    .disabled(!canJump(to: chapter))
                }
            } label: {
                Color.clear.frame(width: menuWidth, height: 48).contentShape(Rectangle())
            }
            .menuOrder(.fixed)
            .menuIndicator(.hidden)
            .buttonStyle(PlayerMenuButtonStyle(onPress: onMenuInteraction))
            .disabled(!isEnabled)
            .accessibilityLabel("视频章节")
            .accessibilityValue(title)
            .accessibilityIdentifier("player.chapters")

            HStack(spacing: 4) {
                Text(title).lineLimit(1).truncationMode(.tail)
                Image(systemName: "chevron.down").font(.app(.caption2, weight: .semibold))
            }
            .font(.app(.caption, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(width: menuWidth, height: 32)
            .playerGlassSurface(in: Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
