import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 官方附加内容是显示器像素边长，不是视频分辨率；旋转不改变长短边。
struct AppRecommendationDisplay: Sendable {
    let shortEdge: Int
    let longEdge: Int

    init?(width: Double, height: Double) {
        guard width.isFinite, height.isFinite, width > 0, height > 0,
              width < Double(Int.max), height < Double(Int.max) else { return nil }
        shortEdge = Int(min(width, height).rounded(.down))
        longEdge = Int(max(width, height).rounded(.down))
        guard shortEdge > 0 else { return nil }
    }

    var playerExtraContent: String {
        #"{"short_edge":"\#(shortEdge)","long_edge":"\#(longEdge)"}"#
    }

    @MainActor
    static func currentScale() -> Double {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        // Use logical display scale, not native pixel scaling or a captured phone's constant.
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return Double(scene?.screen.scale ?? 1)
        #else
        return 1
        #endif
    }

    @MainActor
    static func current() -> Self? {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let screen = (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.screen else { return nil }
        return Self(width: screen.nativeBounds.width, height: screen.nativeBounds.height)
        #else
        return nil
        #endif
    }
}

/// 推荐卡片取流与实际播放器共有的保守能力声明。
/// 不声明未验证的 HDR Vivid、官方私有能力位或内联自动播放功能。
enum AppRecommendationPlaybackCapabilities {
    static let fnval = 16 | 128 | 256 | 2048 // DASH、4K、杜比音轨、AV1；已有取流/解码路径。
}
