import SwiftUI
import UIKit

/// 字体风格：默认使用系统字体，宋体使用内置的思源宋体（SIL OFL）。
///
/// iOS 没有简体宋体，系统衬线体对中文会退回苹方，中英文会一边衬线一边黑体。
/// 内置的思源宋体同时含拉丁字母和简体汉字，同一套字形覆盖中英文，风格自然统一。
/// 风格在启动时确定，改动后重新打开生效，与界面语言一致。
enum AppFontStyle: String, CaseIterable, Identifiable {
    case standard, songti

    static let storageKey = "neobili.fontStyle"

    /// 本次启动实际使用的风格；设置页据此提示「重新打开后生效」。
    static let launched = stored()

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: String(localized: "默认字体")
        case .songti: String(localized: "宋体")
        }
    }

    static func stored(_ defaults: UserDefaults = .standard) -> AppFontStyle {
        defaults.string(forKey: storageKey).flatMap(AppFontStyle.init(rawValue:)) ?? .standard
    }
}

/// 全 App 取字体的统一入口。默认风格返回与原来完全相同的系统字体，宋体风格返回内置字体。
///
/// 内置字体只有常规和半粗两个字重：中等及以下用常规，半粗及以上用半粗。
enum AppFont {
    static let regularName = "SourceHanSerifCN-Regular"
    static let semiboldName = "SourceHanSerifCN-SemiBold"

    /// 系统各文字样式在标准档位的字号，内置字体按同样的基准缩放。
    static func baseSize(_ style: UIFont.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title1: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption1: 12
        case .caption2: 11
        default: 17
        }
    }

    static func uiFont(ofSize size: CGFloat, weight: UIFont.Weight = .regular,
                       style: AppFontStyle = .launched) -> UIFont {
        guard style == .songti else { return .systemFont(ofSize: size, weight: weight) }
        let name = weight.rawValue >= UIFont.Weight.semibold.rawValue ? semiboldName : regularName
        return UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    /// 随动态字体缩放的文字样式字体；`weight` 为空时保持样式自带字重。
    static func preferred(_ textStyle: UIFont.TextStyle, weight: UIFont.Weight? = nil,
                          traits: UITraitCollection? = nil, style: AppFontStyle = .launched) -> UIFont {
        guard style == .songti else {
            let font = traits.map { UIFont.preferredFont(forTextStyle: textStyle, compatibleWith: $0) }
                ?? UIFont.preferredFont(forTextStyle: textStyle)
            guard let weight else { return font }
            return .systemFont(ofSize: font.pointSize, weight: weight)
        }
        let resolved = weight ?? (textStyle == .headline ? .semibold : .regular)
        let base = uiFont(ofSize: baseSize(textStyle), weight: resolved, style: style)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: base, compatibleWith: traits)
    }

    /// 已知字号、需要随动态字体缩放的字体。
    static func scaled(ofSize size: CGFloat, weight: UIFont.Weight = .regular, relativeTo textStyle: UIFont.TextStyle = .body,
                       traits: UITraitCollection? = nil, style: AppFontStyle = .launched) -> UIFont {
        UIFontMetrics(forTextStyle: textStyle).scaledFont(for: uiFont(ofSize: size, weight: weight, style: style),
                                                          compatibleWith: traits)
    }

    /// 导航栏标题和标签栏文字由 UIKit 绘制，启动时按风格设置一次外观。
    @MainActor static func applyChromeAppearance(style: AppFontStyle = .launched) {
        guard style == .songti else { return }
        let largeTitle = preferred(.largeTitle, weight: .semibold, style: style)
        let title = preferred(.headline, weight: .semibold, style: style)
        let navigationBar = UINavigationBar.appearance()
        navigationBar.largeTitleTextAttributes = [.font: largeTitle]
        navigationBar.titleTextAttributes = [.font: title]
    }

    /// SwiftUI `TabView` 背后的 `UITabBarController` 在 iOS 26 上不理会全局的标签项外观，
    /// 要直接改它自己的 `UITabBarAppearance` 和各标签项。保留原有外观，只替换标题字体。
    @MainActor static func applyTabBarFont(to tabBar: UITabBar, style: AppFontStyle = .launched) {
        guard style == .songti else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: preferred(.caption2, weight: .semibold, style: style)]
        func restyled(_ source: UITabBarAppearance) -> UITabBarAppearance {
            let appearance = source.copy()
            for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance,
                           appearance.compactInlineLayoutAppearance] {
                for item in [layout.normal, layout.selected, layout.disabled, layout.focused] {
                    item.titleTextAttributes.merge(attributes) { _, new in new }
                }
            }
            return appearance
        }
        tabBar.standardAppearance = restyled(tabBar.standardAppearance)
        if let edge = tabBar.scrollEdgeAppearance { tabBar.scrollEdgeAppearance = restyled(edge) }
        for item in tabBar.items ?? [] {
            for state in [UIControl.State.normal, .selected] { item.setTitleTextAttributes(attributes, for: state) }
        }
    }
}

extension Font {
    /// 对应系统文字样式，随动态字体缩放；宋体风格下换成内置字体。
    static func app(_ textStyle: Font.TextStyle, weight: Font.Weight? = nil,
                    style: AppFontStyle = .launched) -> Font {
        guard style == .songti else {
            let base = Font.system(textStyle)
            return weight.map { base.weight($0) } ?? base
        }
        let resolved = weight ?? (textStyle == .headline ? .semibold : .regular)
        let semibold = [Font.Weight.semibold, .bold, .heavy, .black].contains(resolved)
        return .custom(semibold ? AppFont.semiboldName : AppFont.regularName,
                       size: AppFont.baseSize(textStyle.uiTextStyle), relativeTo: textStyle)
    }
}

private extension Font.TextStyle {
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .body: .body
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        @unknown default: .body
        }
    }
}

private struct AppFontStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        // 没有显式字体的文字继承环境字体，宋体风格下统一成正文样式。
        if AppFontStyle.launched == .songti {
            content.font(.app(.body))
        } else {
            content
        }
    }
}

extension View {
    /// 在根视图和每个独立呈现的模态根部调用，让没有显式字体的文字也使用所选风格。
    func appFontStyle() -> some View { modifier(AppFontStyleModifier()) }
}
