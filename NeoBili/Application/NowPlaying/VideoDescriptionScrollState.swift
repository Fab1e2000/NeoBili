import Foundation

/// Scroll persistence does not publish per-frame offsets back through SwiftUI.
@MainActor
final class VideoDescriptionScrollState {
    /// 离列表顶部滚了多远（不含顶部边距），顶部边距变化后仍能恢复到同一位置。
    var offset: CGFloat = 0
}
