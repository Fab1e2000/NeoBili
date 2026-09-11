import Foundation
import CoreGraphics

/// 非全屏播放器按画面比例排版；较长的竖屏画面保留简介和评论的空间。
enum InlineVideoLayout {
    static let defaultAspectRatio = 16.0 / 9.0

    /// 接口宽高是编码尺寸，旋转 90/270 度后才是用户最终看到的画幅。
    static func aspectRatio(width: Int, height: Int, rotation: Int = 0) -> Double? {
        guard width > 0, height > 0 else { return nil }
        let normalizedRotation = ((rotation % 360) + 360) % 360
        if normalizedRotation == 90 || normalizedRotation == 270 {
            return Double(height) / Double(width)
        }
        return Double(width) / Double(height)
    }

    static func height(
        for size: CGSize,
        aspectRatio: Double? = nil,
        hidesPortraitVideos: Bool = false
    ) -> CGFloat {
        guard size.width.isFinite, size.height.isFinite else { return 0 }
        let shortEdge = min(size.width, size.height)
        guard shortEdge > 0 else { return 0 }

        let ratio: Double
        if !hidesPortraitVideos, let aspectRatio, aspectRatio.isFinite, aspectRatio > 0 {
            ratio = aspectRatio
        } else {
            ratio = defaultAspectRatio
        }

        // PiliPlus 的竖屏上限：屏幕长边的 65%，且至少容纳一个正方形。
        // 按长短边计算，旋转尚未完成时也不会用横屏宽度把画面撑得过高。
        let maximumHeight = max(max(size.width, size.height) * 0.65, shortEdge)
        return min(shortEdge / CGFloat(ratio), maximumHeight).rounded()
    }
}
