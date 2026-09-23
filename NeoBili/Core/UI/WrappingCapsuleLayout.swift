import SwiftUI

/// Natural-width capsules, constrained only by the available row width.
struct WrappingCapsuleLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.reduce(0) { $0 + $1.sizeThatFits(.unspecified).width + spacing }
        let frames = frames(width: width, subviews: subviews)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, frame) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                       anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }
    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        Self.arrange(sizes: subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)) },
                     width: width, spacing: spacing)
    }
    static func arrange(sizes: [CGSize], width: CGFloat, spacing: CGFloat) -> [CGRect] {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        return sizes.map { size in
            let size = CGSize(width: min(size.width, width), height: size.height)
            if x > 0 && x + size.width > width {
                x = 0; y += rowHeight; rowHeight = 0
            }
            let frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            return frame
        }
    }
}
