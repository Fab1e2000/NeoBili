import SwiftUI

/// 播放时间的统一写法（`分:秒`），进度条和时间文字共用，避免两处显示不一致。
enum PlaybackTime {
    static func text(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
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
            if editing {
                draft = clamped(position)
                isEditing = true
            } else if isEditing {
                isEditing = false
                onScrubEnd(draft)
            }
        })
        // 官方媒体样式不需要透明 Slider 叠加自绘轨道，避免两份坐标／状态不同步。
        .sliderThumbVisibility(isEditing ? .visible : .hidden)
        .controlSize(.small)
        .tint(.white)
        .frame(height: 48)
        .contentShape(Rectangle())
        .accessibilityLabel("播放进度")
        .accessibilityValue("\(PlaybackTime.text(isEditing ? draft : position))，共 \(PlaybackTime.text(duration))")
    }
}
