import Foundation
import CoreGraphics

/// 一次横滑使用起手时的播放快照；播放时钟继续走动也不会推动预览目标。
struct PlayerSeekGestureState {
    let origin: Double
    let duration: Double
    let width: CGFloat
    let initialTranslation: CGFloat
    private(set) var target: Double
    private(set) var isCancelled = false

    init?(position: Double, duration: Double, width: CGFloat, translation: CGFloat) {
        guard position.isFinite, duration.isFinite, duration > 0,
              width.isFinite, width > 0, translation.isFinite else { return nil }
        origin = min(max(position, 0), duration)
        target = origin
        self.duration = duration
        self.width = width
        initialTranslation = translation
    }

    var delta: Double { target - origin }

    mutating func update(translation: CGFloat, location: CGPoint, height: CGFloat) {
        guard translation.isFinite else { return }
        isCancelled = location.y <= height * 0.125
            && (location.x <= width * 0.125 || location.x >= width * 0.875)
        // 一屏最多 90 秒；短视频按自身时长缩小范围，避免一滑就到片尾。
        let offset = Double((translation - initialTranslation) / width) * min(90, duration)
        target = min(max(origin + offset, 0), duration)
    }
}
