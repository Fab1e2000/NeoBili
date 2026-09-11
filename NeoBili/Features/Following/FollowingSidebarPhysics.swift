import Foundation

/// 横向展开的唯一坐标系：手指位移直接换算为进度，松手才进入物理停靠。
enum FollowingSidebarPhysics {
    static let displacement: CGFloat = 96
    static let angularFrequency: CGFloat = 24

    struct Sample: Equatable {
        var progress: CGFloat
        var velocity: CGFloat
    }

    static func clamp(_ progress: CGFloat) -> CGFloat {
        progress.isFinite ? min(max(progress, 0), 1) : 0
    }

    static func dragProgress(start: CGFloat, translation: CGFloat) -> CGFloat {
        clamp(start + (translation.isFinite ? translation : 0) / displacement)
    }

    static func target(progress: CGFloat, velocity: CGFloat) -> CGFloat {
        let speed = velocity.isFinite ? velocity : 0
        return clamp(progress) + speed / displacement * 0.12 >= 0.5 ? 1 : 0
    }

    /// 临界阻尼方程的解析解，60/120Hz 和掉帧时结果一致，不使用逐帧欧拉积分。
    /// velocity 的单位为每秒进度，保留松手瞬间的速度；两端是实际布局边界。
    static func advance(_ sample: Sample, toward target: CGFloat, elapsed: TimeInterval) -> Sample {
        let next = advanceUnbounded(sample, toward: clamp(target), elapsed: elapsed)
        if next.progress <= 0 { return Sample(progress: 0, velocity: max(0, next.velocity)) }
        if next.progress >= 1 { return Sample(progress: 1, velocity: min(0, next.velocity)) }
        return next
    }

    static func advanceUnbounded(_ sample: Sample, toward target: CGFloat, elapsed: TimeInterval,
                                 frequency: CGFloat = angularFrequency) -> Sample {
        guard elapsed.isFinite, elapsed > 0 else { return sample }
        let x = sample.progress - target
        let velocity = sample.velocity.isFinite ? sample.velocity : 0
        let coefficient = velocity + frequency * x
        let time = CGFloat(elapsed)
        let decay = exp(-frequency * time)
        let progress = target + (x + coefficient * time) * decay
        let nextVelocity = (velocity - frequency * coefficient * time) * decay
        return Sample(progress: progress, velocity: nextVelocity)
    }
}

/// 只缩放内容，不重排卡片宽度；补偿缩放前的视口高度，保留上下安全区衔接。
struct FollowingFeedGeometry: Equatable {
    let scale: CGFloat
    let displacement: CGFloat
    let unscaledHeight: CGFloat

    init(width: CGFloat, height: CGFloat, progress: CGFloat) {
        let width = width.isFinite ? max(0, width) : 0
        let height = height.isFinite ? max(0, height) : 0
        let progress = FollowingSidebarPhysics.clamp(progress)
        displacement = min(FollowingSidebarPhysics.displacement, width * 0.5) * progress
        scale = width > 0 ? (width - displacement) / width : 1
        unscaledHeight = height / scale
    }
}
