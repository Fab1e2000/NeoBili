import SwiftUI

extension EnvironmentValues {
    /// 打开「我的」页面。由根视图的 `mineSheetHost()` 提供。
    @Entry var openMine: EnvironmentAction<Void>? = nil
}

/// 自绘页头：左侧大标题，右侧头像玻璃按钮。主页面已改用 `rootPageChrome` 的原生标题，这里只剩推荐列表里不再启用的页头行。
/// 头像是「我的」页面的唯一入口，点按后以卡片从底部弹出。
struct PageHeader: View {
    let title: String
    /// 放进 UIKit 格子里时拿不到根视图的环境，由外层把打开动作传进来。
    var onOpenMine: (() -> Void)?
    @Environment(AccountStore.self) private var account
    @Environment(\.openMine) private var openMine

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 16)
            Button { (onOpenMine ?? { openMine?(()) })() } label: {
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
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                // 头像完整保留在玻璃表面上方，外圈只留一圈细窄的透明间隙。
                .padding(2)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .background {
                    Circle()
                        .fill(.clear)
                        .glassEffect(.clear.interactive(), in: .circle)
                }
                .overlay {
                    Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("我的")
            .accessibilityHint("打开个人页面")
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 原生大标题

/// 其它主页面的原生栏内大标题：标题与头像入口同在导航栏一行。
/// 头像在工具栏里不套系统玻璃胶囊，只保留圆形头像和细描边。
struct RootPageChrome: ViewModifier {
    let title: String
    @Environment(AccountStore.self) private var account
    @Environment(\.openMine) private var openMine

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbarVisibility(.visible, for: .navigationBar)
            .modifier(MinimizingNavigationBar())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { openMine?(()) } label: { avatar }
                        .accessibilityLabel("我的")
                        .accessibilityHint("打开个人页面")
                }
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
        .frame(width: 32, height: 32)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5) }
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }
}

/// 保持顶部安全区稳定，避免导航栏收起后点标签回顶需要点两次。
private struct MinimizingNavigationBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 27.0, *) {
            content
                .toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)
                .toolbarMinimizationSafeAreaAdjustment(.disabled, for: .navigationBar)
        } else {
            content
        }
    }
}

extension View {
    func rootPageChrome(title: String) -> some View {
        modifier(RootPageChrome(title: title))
    }
}
