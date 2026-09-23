import SwiftUI
import UIKit

/// 所有头像与背景共用的胶囊：靠屏幕边缘的一侧保持直线，内侧平滑突出。
/// 选择器与页面凹口共用同一条轮廓，凹口沿法线偏移而非水平平移。
enum FollowingSidebarContour {
    static let spine: CGFloat = 56
    static let bulge: CGFloat = 32
    static let reach: CGFloat = 100
    static let gap: CGFloat = 8

    static func width(at y: CGFloat, base: CGFloat = spine, amplitude: CGFloat = bulge) -> CGFloat {
        base + (abs(y) < reach ? amplitude * (1 + cos(.pi * y / reach)) / 2 : 0)
    }

    static func slope(at y: CGFloat, amplitude: CGFloat = bulge) -> CGFloat {
        abs(y) < reach ? -amplitude * .pi / (2 * reach) * sin(.pi * y / reach) : 0
    }

    static func pageEdge(at y: CGFloat) -> CGPoint {
        let derivative = slope(at: y)
        let normalLength = sqrt(1 + derivative * derivative)
        return CGPoint(x: width(at: y) + gap / normalLength,
                       y: y - gap * derivative / normalLength)
    }
}

struct FollowingSidebarShape: Shape {
    static let width: CGFloat = 88
    let side: FollowingSidebarSide
    var focusY: CGFloat? = nil
    var spineWidth: CGFloat = FollowingSidebarContour.spine
    var bulge: CGFloat = FollowingSidebarContour.bulge

    func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let middle = focusY ?? rect.height / 2
        let base = min(spineWidth, rect.width)
        let amplitude = min(bulge, rect.width - base)
        func width(_ y: CGFloat) -> CGFloat {
            FollowingSidebarContour.width(at: y - middle, base: base, amplitude: amplitude)
        }
        func slope(_ y: CGFloat) -> CGFloat {
            FollowingSidebarContour.slope(at: y - middle, amplitude: amplitude)
        }
        // 圆帽直接接入内侧曲线，而不是用另一层圆角矩形截断曲线。
        var topRadius = min(base / 2, rect.height / 2)
        var bottomRadius = topRadius
        for _ in 0..<6 {
            topRadius = min(width(topRadius) / 2, rect.height / 2)
            bottomRadius = min(width(rect.height - bottomRadius) / 2, rect.height / 2)
        }
        let topY = topRadius
        let bottomY = rect.height - bottomRadius
        let topWidth = width(topY)
        let bottomWidth = width(bottomY)
        let k: CGFloat = 0.55228475
        var path = Path()
        path.move(to: CGPoint(x: 0, y: topY))
        path.addCurve(to: CGPoint(x: topWidth / 2, y: 0),
                      control1: CGPoint(x: 0, y: topY * (1 - k)),
                      control2: CGPoint(x: topWidth / 2 * (1 - k), y: 0))
        path.addCurve(to: CGPoint(x: topWidth, y: topY),
                      control1: CGPoint(x: topWidth / 2 * (1 + k), y: 0),
                      control2: CGPoint(x: topWidth - slope(topY) * topRadius * k, y: topY - topRadius * k))
        // 固定段数和路径拓扑，A/B 及不同高度间可直接插值，不产生尖角。
        for segment in 0..<32 {
            let y0 = topY + (bottomY - topY) * CGFloat(segment) / 32
            let y1 = topY + (bottomY - topY) * CGFloat(segment + 1) / 32
            let step = (y1 - y0) / 3
            path.addCurve(to: CGPoint(x: width(y1), y: y1),
                          control1: CGPoint(x: width(y0) + slope(y0) * step, y: y0 + step),
                          control2: CGPoint(x: width(y1) - slope(y1) * step, y: y1 - step))
        }
        path.addCurve(to: CGPoint(x: bottomWidth / 2, y: rect.height),
                      control1: CGPoint(x: bottomWidth + slope(bottomY) * bottomRadius * k, y: bottomY + bottomRadius * k),
                      control2: CGPoint(x: bottomWidth / 2 * (1 + k), y: rect.height))
        path.addCurve(to: CGPoint(x: 0, y: bottomY),
                      control1: CGPoint(x: bottomWidth / 2 * (1 - k), y: rect.height),
                      control2: CGPoint(x: 0, y: rect.height - bottomRadius * (1 - k)))
        path.closeSubpath()
        if side == .right {
            path = path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.width, ty: 0))
        }
        return path.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}

/// 实际焦点行到视窗中线的距离，也用于真机回归检查重新展开后的定位。
struct FollowingSidebarAlignmentKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() { value = next }
    }
}
