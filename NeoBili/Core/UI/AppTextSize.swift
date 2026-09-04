import SwiftUI

/// 全 App 的文字大小。
///
/// 这里刻意**不跟随**系统的动态字体：两套机制同时生效时，同一个界面在不同
/// 设备上会得到互相叠加的两次缩放，排版没法预期。改成由根视图统一注入一个
/// 固定档位后，系统设置不再参与，App 内这一个滑杆就是唯一的来源。
///
/// 档位本身仍用系统的 `DynamicTypeSize`，所以 `.font(.subheadline)` 这类语义
/// 字号会照常按 Apple 的比例缩放，不需要给每处文字手写字号。
enum AppTextSize {
    /// 与设置页共用的存储键。
    static let storageKey = "neobili.textSize"

    /// 滑杆上的七个档位，和系统「文字大小」里那七个刻度一一对应。
    static let steps: [DynamicTypeSize] = [
        .xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge
    ]

    /// 默认停在 `.large`，也就是 iOS 出厂时的档位。
    static let defaultIndex = 3

    static func size(at index: Int) -> DynamicTypeSize {
        steps[min(max(index, 0), steps.count - 1)]
    }
}

/// 把当前档位重新注入到模态呈现（sheet / fullScreenCover）内容的根部。
///
/// 根视图虽然已经给整棵树注入了 `dynamicTypeSize`，但每个 sheet/fullScreenCover
/// 都由独立的 UIHostingController 呈现，它会按自身的 trait 重建这份环境值——
/// 也就是退回跟随系统设置——根上的注入到不了那里（自定义的 `.environment`
/// 不受影响，所以账号这些 store 一直好好的）。视频页和它的评论区正是
/// fullScreenCover 里的内容，之前调滑杆没反应就是这个原因。每个模态的
/// 内容根部补一次这个修饰符即可。
private struct AppTextSizeModifier: ViewModifier {
    @AppStorage(AppTextSize.storageKey) private var index = AppTextSize.defaultIndex

    func body(content: Content) -> some View {
        content.dynamicTypeSize(AppTextSize.size(at: index))
    }
}

extension View {
    /// 在每个 `.sheet` / `.fullScreenCover` 的内容根部调用，让模态里的文字
    /// 也跟随设置页那根滑杆。
    func appTextSize() -> some View {
        modifier(AppTextSizeModifier())
    }
}
