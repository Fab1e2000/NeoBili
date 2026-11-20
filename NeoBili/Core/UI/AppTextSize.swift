import SwiftUI

/// 根视图统一注入应用选定的 DynamicTypeSize，系统字号不再叠加缩放。
/// 各处语义字体仍按该档位使用系统缩放比例。
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

/// 每个 sheet/fullScreenCover 的独立宿主都需重新注入应用字号，避免使用系统 trait 的档位。
private struct AppTextSizeModifier: ViewModifier {
    @AppStorage(AppTextSize.storageKey) private var index = AppTextSize.defaultIndex

    func body(content: Content) -> some View {
        // 这些入口同时是独立呈现的根部，主题也需在此重新注入。
        content.dynamicTypeSize(AppTextSize.size(at: index)).appTheme().appFontStyle()
    }
}

extension View {
    /// 在每个 `.sheet` / `.fullScreenCover` 的内容根部调用，让模态里的文字
    /// 也跟随设置页那根滑杆。
    func appTextSize() -> some View {
        modifier(AppTextSizeModifier())
    }
}
