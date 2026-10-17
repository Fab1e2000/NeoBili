import Foundation
import CoreGraphics

/// 固定渲染表面的尺寸逻辑，单独拆出来便于单测。
enum PlayerSurfaceGeometry {
    static func displayAspectRatio(_ aspect: Double, rotation: Int64) -> Double? {
        guard aspect.isFinite, aspect > 0 else { return nil }
        let normalized = (rotation % 360 + 360) % 360
        return normalized == 90 || normalized == 270 ? 1 / aspect : aspect
    }

    /// 无论当前设备方向如何，都返回同一个横屏像素尺寸。
    static func stableDrawableSize(for screenSize: CGSize) -> CGSize {
        CGSize(
            width: max(screenSize.width, screenSize.height),
            height: min(screenSize.width, screenSize.height)
        )
    }

    static func pointSize(for pixelSize: CGSize, displayScale: CGFloat) -> CGSize {
        guard displayScale > 0 else { return .zero }
        return CGSize(
            width: pixelSize.width / displayScale,
            height: pixelSize.height / displayScale
        )
    }

    /// mpv 先把画面等比放进固定 surface，再把这块实际画面完整放进页面容器。
    /// 只裁掉 surface 自带的黑边；固定 16:9、竖屏限高和全屏时都不裁视频内容。
    static func presentationScale(
        surfaceSize: CGSize,
        containerSize: CGSize,
        videoAspectRatio: Double? = nil
    ) -> CGFloat {
        guard surfaceSize.width > 0, surfaceSize.height > 0 else { return 1 }
        if let ratio = videoAspectRatio, ratio.isFinite, ratio > 0 {
            let contentWidth = min(surfaceSize.width, surfaceSize.height * ratio)
            let contentHeight = contentWidth / ratio
            return min(containerSize.width / contentWidth, containerSize.height / contentHeight)
        }
        return max(
            containerSize.width / surfaceSize.width,
            containerSize.height / surfaceSize.height
        )
    }
}
