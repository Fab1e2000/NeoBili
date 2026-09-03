import SwiftUI

/// 播放时间的统一写法（`分:秒`），进度条和时间文字共用，避免两处显示不一致。
enum PlaybackTime {
    static func text(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// 自己实现的进度条，用来替换系统 `Slider`。
///
/// 系统滑块只有在手指恰好压住那个圆点时才会移动，稍微偏一点就什么都不做，
/// 用起来像“不跟手”。这里改成：轨道上任意位置按下或拖动，圆点立刻跟到手指处。
/// 本组件不保存位置，只上报手指对应的时间；真正的跳转由外部在手指抬起后执行一次。
struct VideoScrubber: View {
    /// 当前要画出来的位置。拖动时是手指位置，其余时候是播放位置。
    let position: Double
    /// 已经缓冲到的位置，画成一段比进度更靠前的浅色区域。
    let buffered: Double
    let duration: Double
    /// 手指按下和移动时调用，参数是手指对应的时间。只用来更新界面。
    let onScrub: (Double) -> Void
    /// 手指抬起时调用一次，由外部执行跳转。
    let onScrubEnd: (Double) -> Void

    /// 看得见的轨道粗细。数字越大，进度条越粗。
    private let trackHeight: CGFloat = 3
    /// 圆形滑块的直径。
    private let knobDiameter: CGFloat = 12
    /// 可以按到的高度。轨道很细，热区必须比它大得多才好操作。
    private let touchHeight: CGFloat = 44
    /// 无障碍“增加/减少”一次调整的秒数。
    private let accessibilityStep: Double = 5

    var body: some View {
        GeometryReader { geometry in
            // 圆点的圆心要能停在轨道两端，所以可移动范围要去掉一个圆点的宽度。
            let travel = max(geometry.size.width - knobDiameter, 1)
            let progress = fraction(of: position)
            let bufferedProgress = max(fraction(of: buffered), progress)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.28))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(.white.opacity(0.45))
                    .frame(width: knobDiameter / 2 + travel * bufferedProgress, height: trackHeight)

                Capsule()
                    .fill(.white)
                    .frame(width: knobDiameter / 2 + travel * progress, height: trackHeight)

                Circle()
                    .fill(.white)
                    .frame(width: knobDiameter, height: knobDiameter)
                    .offset(x: travel * progress)
            }
            .frame(width: geometry.size.width, height: touchHeight)
            .contentShape(Rectangle())
            // minimumDistance 为 0，所以轻点一下也会先 onChanged 再 onEnded，
            // 点击和拖动因此走同一条路径：先跟手，松开再跳转。
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { onScrub(time(atX: $0.location.x, travel: travel)) }
                    .onEnded { onScrubEnd(time(atX: $0.location.x, travel: travel)) }
            )
        }
        .frame(height: touchHeight)
        .accessibilityElement()
        .accessibilityLabel("播放进度")
        .accessibilityValue("\(PlaybackTime.text(position)) / \(PlaybackTime.text(duration))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onScrubEnd(position + accessibilityStep)
            case .decrement: onScrubEnd(position - accessibilityStep)
            @unknown default: break
            }
        }
    }

    /// duration 还没拿到时用 1 秒占位，进度就停在开头，不会除以 0。
    private var span: Double {
        duration.isFinite && duration > 0 ? duration : 1
    }

    private func fraction(of seconds: Double) -> Double {
        guard seconds.isFinite else { return 0 }
        return min(max(seconds / span, 0), 1)
    }

    private func time(atX x: CGFloat, travel: CGFloat) -> Double {
        let ratio = min(max(Double((x - knobDiameter / 2) / travel), 0), 1)
        return ratio * span
    }
}
