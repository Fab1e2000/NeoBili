import SwiftUI

#if DEBUG
/// Geometry-only diagnostics. Production views publish anchors without drawing
/// markers; the comment spacing tests supply their own rendering overlay.
struct CommentReplyLayoutBoundsKey: PreferenceKey {
    enum Region: Hashable { case content, block, divider }
    static var defaultValue: [Region: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [Region: Anchor<CGRect>], nextValue: () -> [Region: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
#endif
