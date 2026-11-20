import SwiftUI
import UIKit

extension EnvironmentValues {
    /// 打开「我的」页面。由根视图的 `mineSheetHost()` 提供。
    @Entry var openMine: EnvironmentAction<Void>? = nil
}

/// 主页面头像左侧的附加按钮。头像始终贴在最右，各页位置保持一致。
@MainActor
@Observable
final class RootToolbarAccessory {
    struct ButtonSpec {
        var title: String
        var systemImage: String
        var identifier: String
        var disabled: Bool
        var action: () -> Void
    }

    var button: ButtonSpec?
}

// MARK: - 原生大标题

/// 主页面的原生栏内大标题，右侧放置自绘圆形玻璃头像入口。
struct RootPageChrome: ViewModifier {
    let title: String
    /// 导航栏下方还有常驻的切换条时，顶部安全区要跟着导航栏收起，切换条才会上移。
    let barFollowsCollapse: Bool
    @Environment(AccountStore.self) private var account
    @Environment(\.openMine) private var openMine
    @Environment(RootToolbarAccessory.self) private var toolbarAccessory: RootToolbarAccessory?

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbarVisibility(.visible, for: .navigationBar)
            .modifier(MinimizingNavigationBar(adjustsSafeArea: barFollowsCollapse))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        if let button = toolbarAccessory?.button {
                            Button(button.title, systemImage: button.systemImage, action: button.action)
                                .labelStyle(.iconOnly)
                                .buttonStyle(.glass)
                                .buttonBorderShape(.circle)
                                .disabled(button.disabled)
                                .accessibilityIdentifier(button.identifier)
                        }
                        Button { openMine?(()) } label: { avatar }
                            .buttonStyle(.plain)
                            .accessibilityLabel("我的")
                            .accessibilityHint("打开个人页面")
                    }
                }
                // 系统工具栏玻璃会按内容撑成胶囊；关掉它，圆形玻璃由头像自己绘制。
                .sharedBackgroundVisibility(.hidden)
            }
    }

    private var avatar: some View {
        Group {
            if let url = account.profile?.secureAvatarURL {
                BiliImage(url: url)
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(Circle())
        // 头像完整保留在玻璃表面上方，外圈只留一圈细窄的透明间隙。
        .padding(3)
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .background { Circle().fill(.clear).glassEffect(.clear.interactive(), in: .circle) }
        .overlay { Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5).allowsHitTesting(false) }
    }
}

/// iOS 27 起随下滑收起导航栏；按页面布局选择是否让顶部安全区同步收缩。
private struct MinimizingNavigationBar: ViewModifier {
    let adjustsSafeArea: Bool

    func body(content: Content) -> some View {
        if #available(iOS 27.0, *) {
            content
                .toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)
                .toolbarMinimizationSafeAreaAdjustment(adjustsSafeArea ? .enabled : .disabled, for: .navigationBar)
        } else {
            content
        }
    }
}

extension View {
    func rootPageChrome(title: String, barFollowsCollapse: Bool = false) -> some View {
        modifier(RootPageChrome(title: title, barFollowsCollapse: barFollowsCollapse))
    }

    /// iOS 26 的导航栏默认是玻璃材质，SwiftUI 的 toolbarBackground 会被它盖住。
    /// 页面需要和吸顶分组标题拼成一整条时，用 UIKit 的不透明外观固定柱底色。
    func opaqueNavigationBarBackground(_ color: UIColor = .systemGroupedBackground) -> some View {
        background {
            OpaqueNavigationBarBackground(color: color)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// 配置所在导航栏的外观为不透明底色；SwiftUI 每次重算工具栏后这里会再应用一遍。
private struct OpaqueNavigationBarBackground: UIViewRepresentable {
    let color: UIColor

    func makeUIView(context: Context) -> ObserverView { ObserverView(color: color) }
    func updateUIView(_ view: ObserverView, context: Context) {
        view.color = color
        view.apply()
    }

    final class ObserverView: UIView {
        var color: UIColor
        private var applied: UINavigationBarAppearance?

        init(color: UIColor) {
            self.color = color
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            apply()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            apply()
        }

        func apply() {
            guard let bar = enclosingNavigationBar() else { return }
            // 外观没被系统重新覆盖时不做无谓的写入。
            if let applied, bar.standardAppearance === applied, bar.scrollEdgeAppearance === applied { return }
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = color
            appearance.shadowColor = .clear
            bar.standardAppearance = appearance
            bar.compactAppearance = appearance
            bar.scrollEdgeAppearance = appearance
            bar.compactScrollEdgeAppearance = appearance
            applied = appearance
        }

        private func enclosingNavigationBar() -> UINavigationBar? {
            var ancestor = superview
            while let view = ancestor {
                if let bar = view.subviews.first(where: { $0 is UINavigationBar }) as? UINavigationBar {
                    return bar
                }
                ancestor = view.superview
            }
            var responder: UIResponder? = self
            while let current = responder {
                if let navigation = current as? UINavigationController { return navigation.navigationBar }
                responder = current.next
            }
            return nil
        }
    }
}
