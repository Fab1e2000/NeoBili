import SwiftUI

struct VideoSeekPreview: View {
    let video: VideoPreviewID
    let seconds: Double
    let store: VideoStoryboardStore

    var body: some View {
        let tile = store.storyboard?.tile(at: seconds)
        VStack(spacing: 4) {
            if let frame = store.frame(at: seconds) {
                Image(uiImage: frame).resizable().scaledToFit()
                    .frame(height: 74)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                // Do not present a generic picture as if it were a video frame.
                // The timestamp remains useful even if the server has no shots.
                Group {
                    if store.failed || tile.map({ store.failedURLs.contains($0.url) }) == true {
                        VStack(spacing: 3) {
                            Text("暂无预览")
                            Text("稍后拖动重试")
                        }.font(.caption2).foregroundStyle(.secondary)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(height: 74)
            }
            Text(PlaybackTime.text(seconds)).font(.caption.monospacedDigit().weight(.semibold))
        }
        .padding(5)
        // 和播放器控件同一层，跟着用透明变体；下面有控件层的调暗层托底。
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 10))
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
        .task(id: video) {
            // A failed preload must not disable previews for the whole session.
            // Cached/in-flight metadata is reused; a later drag can retry failure.
            await store.load(video)
        }
        .task(id: tile?.url) { await store.prepare(at: seconds) }
    }
}

struct VideoScrubPreviewPosition {
    let bounds: Anchor<CGRect>
    let video: VideoPreviewID
    let seconds: Double
    let duration: Double
}

struct VideoScrubPreviewPreference: PreferenceKey {
    static var defaultValue: VideoScrubPreviewPosition? { nil }
    static func reduce(value: inout VideoScrubPreviewPosition?, nextValue: () -> VideoScrubPreviewPosition?) {
        value = nextValue() ?? value
    }
}
