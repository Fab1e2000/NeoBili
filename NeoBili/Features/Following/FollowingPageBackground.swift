import SwiftUI

/// 独立观察展开进度，整份动态数据不参与逐帧背景重绘。
struct FollowingPageBackground: View {
    let motion: FollowingSidebarMotion
    let side: FollowingSidebarSide
    let topInset: CGFloat
    let bottomInset: CGFloat

    var body: some View {
        FollowingPageEdgeShape(side: side, progress: motion.progress,
                               topInset: topInset, bottomInset: bottomInset)
            .fill(Color(uiColor: .systemBackground))
    }
}

/// 覆盖整个页面与上下安全区的连续底板，侧边保留等距凹口。
private struct FollowingPageEdgeShape: Shape {
    let side: FollowingSidebarSide
    var progress: CGFloat
    let topInset: CGFloat
    let bottomInset: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let middle = rect.minY + topInset + (rect.height - topInset - bottomInset) / 2
        let expansion = min(max(progress, 0), 1)
        let reach = min(FollowingSidebarContour.reach, max(0, rect.height - topInset - bottomInset) / 2)
        // 底板边缘直接使用屏幕坐标，顶端、凹口、底端不再分开拼接。
        func point(at y: CGFloat) -> CGPoint {
            let edge = FollowingSidebarContour.pageEdge(at: y)
            return CGPoint(x: rect.minX + edge.x * expansion,
                           y: middle + y + (edge.y - y) * expansion)
        }
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: point(at: -reach).x, y: rect.minY))
        // 每半点一个采样，保持固定拓扑，展开和收起时仍可连续插值。
        for index in 0...400 {
            path.addLine(to: point(at: -reach + 2 * reach * CGFloat(index) / 400))
        }
        path.addLine(to: CGPoint(x: point(at: reach).x, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        if side == .right {
            return path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1,
                                                 tx: rect.minX + rect.maxX, ty: 0))
        }
        return path
    }
}

/// 选择器展开时的全宽顶部模糊，浓度跟随展开进度；下缘与页头对齐成切边。
/// 单独一个视图读取逐帧的进度，拖动时不会让整个关注页重算。
struct FollowingExpandedTopBlur: View {
    let motion: FollowingSidebarMotion
    let topInset: CGFloat

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .frame(height: topInset)
            .offset(y: -topInset)
            .opacity(motion.progress)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
