import Foundation
import CoreGraphics

enum MiniPlayerLayout {
    static func fittedSize(_ size: CGSize, in bounds: CGRect) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = max(0, min(1, bounds.width / size.width, bounds.height / size.height))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    static func size(in available: CGSize, aspectRatio: Double?) -> CGSize {
        let ratio = aspectRatio.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 16.0 / 9
        // 极窄视频在窗内等比显示；可用空间允许时，至少保留三个 44pt 按钮。
        let layoutRatio = min(max(ratio, 9.0 / 16), 2.4)
        let maximumWidth = max(0, min(240, available.width * 0.6))
        let maximumHeight = max(0, min(280, available.height * 0.45))
        let width = min(max(0, available.width), max(144, min(maximumWidth, maximumHeight * layoutRatio)))
        return CGSize(width: width, height: min(max(0, available.height), width / layoutRatio))
    }

    static func center(anchor: CGPoint, size: CGSize, in bounds: CGRect) -> CGPoint {
        let travelX = max(0, bounds.width - size.width)
        let travelY = max(0, bounds.height - size.height)
        return CGPoint(
            x: bounds.minX + min(size.width, bounds.width) / 2 + min(max(anchor.x, 0), 1) * travelX,
            y: bounds.minY + min(size.height, bounds.height) / 2 + min(max(anchor.y, 0), 1) * travelY
        )
    }

    static func anchor(for center: CGPoint, size: CGSize, in bounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max((center.x - bounds.minX - size.width / 2) / max(1, bounds.width - size.width), 0), 1),
            y: min(max((center.y - bounds.minY - size.height / 2) / max(1, bounds.height - size.height), 0), 1)
        )
    }

    static func clampedCenter(_ center: CGPoint, size: CGSize, in bounds: CGRect) -> CGPoint {
        self.center(anchor: anchor(for: center, size: size, in: bounds), size: size, in: bounds)
    }

    /// UIKit 点/秒速度投影到短暂惯性终点，决定停靠侧和纵向位置。
    static func restingAnchor(center: CGPoint, velocity: CGPoint, size: CGSize, in bounds: CGRect) -> CGPoint {
        let velocity = CGPoint(x: velocity.x.isFinite ? velocity.x : 0,
                               y: velocity.y.isFinite ? velocity.y : 0)
        let projected = CGPoint(x: center.x + velocity.x * 0.16, y: center.y + velocity.y * 0.16)
        var anchor = anchor(for: projected, size: size, in: bounds)
        anchor.x = projected.x < bounds.midX ? 0 : 1
        return anchor
    }

    static func springVelocity(_ velocity: CGPoint, from start: CGPoint, to end: CGPoint) -> CGVector {
        func normalized(_ speed: CGFloat, distance: CGFloat) -> CGFloat {
            guard speed.isFinite, abs(distance) > 1 else { return 0 }
            return min(max(speed / distance, -20), 20)
        }
        return CGVector(dx: normalized(velocity.x, distance: end.x - start.x),
                        dy: normalized(velocity.y, distance: end.y - start.y))
    }
}
