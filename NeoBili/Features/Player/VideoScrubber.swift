import NeoBiliDomain
import SwiftUI

/// 播放时间的统一写法（`分:秒`），进度条和时间文字共用，避免两处显示不一致。
enum PlaybackTime {
    static func text(_ seconds: Double, minimumMinuteDigits: Int = 1) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%0*lld:%02lld", Int32(minimumMinuteDigits), total / 60, total % 60)
    }
}

/// iOS 26 原生无常驻滑块的媒体进度条：显示与触摸始终由同一个 SwiftUI Slider 管理。
/// 拖动时显示系统滑块，结束后恢复细轨道；仅结束拖动／辅助功能调节时实际 seek。
struct VideoScrubber: View {
    let position: Double
    let buffered: Double
    let duration: Double
    let onScrub: (Double) -> Void
    let onScrubEnd: (Double) -> Void
    var previewVideo: VideoPreviewID? = nil
    var chapters: [VideoChapter] = []
    let onEditingChanged: (Bool) -> Void
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var isEditing = false
    @State private var draft: Double = 0

    private var total: Double { duration.isFinite && duration > 0 ? duration : 1 }
    private func clamped(_ value: Double) -> Double { value.isFinite ? min(max(value, 0), total) : 0 }

    var body: some View {
        Slider(value: Binding(
            get: { isEditing ? draft : clamped(position) },
            set: { value in
                draft = clamped(value)
                onScrub(draft)
                // VoiceOver/键盘可能只修改值，不进入手指拖动会话。
                if !isEditing { onScrubEnd(draft) }
            }
        ), in: 0...total, onEditingChanged: { editing in
            guard editing != isEditing else { return }
            if editing {
                draft = clamped(position)
            }
            isEditing = editing
            if !editing { onScrubEnd(draft) }
            onEditingChanged(editing)
        })
        .sliderThumbVisibility(isEditing ? .visible : .hidden)
        .controlSize(.small)
        .tint(.white)
        .frame(height: 48)
        .overlay {
            if !chapters.isEmpty, duration.isFinite, duration > 0 {
                Canvas { context, size in
                    let inset: CGFloat = isEditing ? 9 : 3
                    let trackWidth = max(0, size.width - inset * 2)
                    for chapter in chapters where chapter.from > 0 && chapter.from < duration {
                        let offset = trackWidth * (chapter.from / duration)
                        let x = layoutDirection == .rightToLeft ? size.width - inset - offset : inset + offset
                        let marker = CGRect(x: x - 0.75, y: size.height / 2 - 2.5, width: 1.5, height: 5)
                        context.fill(Path(roundedRect: marker, cornerRadius: 0.75), with: .color(.black.opacity(0.56)))
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .anchorPreference(key: VideoScrubPreviewPreference.self, value: .bounds) { anchor in
            guard isEditing, previewVideo != nil || !chapters.isEmpty else { return nil }
            return VideoScrubPreviewPosition(bounds: anchor, video: previewVideo, seconds: draft, duration: total)
        }
        .contentShape(Rectangle())
        .accessibilityLabel("播放进度")
        .accessibilityIdentifier("player.scrubber")
        .accessibilityValue(String(localized: "\(PlaybackTime.text(isEditing ? draft : position))，共 \(PlaybackTime.text(duration))"))
    }
}
