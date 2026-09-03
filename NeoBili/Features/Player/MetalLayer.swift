import UIKit

/// The layer mpv renders into via the `wid` option trick — mpv drives its own
/// Vulkan (MoltenVK) swapchain against this layer directly; SwiftUI never
/// draws into it.
final class MPVMetalLayer: CAMetalLayer {
    /// MoltenVK sometimes forces `drawableSize` to 1x1 to push through a
    /// pending presentation. Letting that through causes a visible flicker
    /// and can leave the layer stuck at 1x1.
    /// https://github.com/mpv-player/mpv/pull/13651
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            guard Int(newValue.width) > 1, Int(newValue.height) > 1 else { return }
            super.drawableSize = newValue
        }
    }
}
