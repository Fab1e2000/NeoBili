import SwiftUI

extension EnvironmentValues {
    /// 打开「我的」页面，参数是发起页头像的转场 ID。由根视图的 `mineSheetHost()` 提供。
    @Entry var openMine: EnvironmentAction<String>? = nil
}

/// 各主页面共用的页头：左侧大标题，右侧头像玻璃按钮。
/// 头像是「我的」页面的唯一入口，页面从头像原位放大出现、关闭时缩回。
struct PageHeader: View {
    let title: String
    /// 头像作为 zoom 转场起点的 ID。各页面同时存活，所以每页要用不同的 ID。
    let transitionID: String
    /// 放进 UIKit 格子里时拿不到根视图的环境，由外层把打开动作传进来。
    var onOpenMine: (() -> Void)?
    @Environment(AccountStore.self) private var account
    @Environment(\.videoTransitionNamespace) private var transition
    @Environment(\.openMine) private var openMine

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 16)
            Button { (onOpenMine ?? { openMine?(transitionID) })() } label: {
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
            .modifier(AvatarTransitionSource(id: transitionID, namespace: transition))
            .accessibilityLabel("我的")
            .accessibilityHint("打开个人页面")
        }
        .padding(.vertical, 8)
    }
}

private struct AvatarTransitionSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            // matchedTransitionSource 只接受圆角矩形，半径取边长一半即为正圆。
            content.matchedTransitionSource(id: id, in: namespace) {
                $0.clipShape(RoundedRectangle(cornerRadius: 22))
            }
        } else {
            content
        }
    }
}

// MARK: - 随内容滚动的页头

/// 标题栏随内容滚动时，外层页面不再固定显示页头，而是通过环境把页头交给列表，
/// 由列表插在内容最上方。列表视图也会出现在别处（如「我的」卡片），那里不提供就不显示。
struct ScrollingPageHeader: Equatable {
    let title: String
    let transitionID: String
}

extension EnvironmentValues {
    @Entry var scrollingPageHeader: ScrollingPageHeader? = nil
}

extension View {
    /// 加载中、空列表、出错这些状态没有可滚动的内容，随内容滚动的页头直接放在顶部。
    func scrollingPageHeaderAbove() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) { ScrollingPageHeaderRow() }
    }
}

/// 列表内容的第一行：环境里有随内容滚动的页头时显示它，否则什么都不占。
struct ScrollingPageHeaderRow: View {
    @Environment(\.scrollingPageHeader) private var header

    var body: some View {
        if let header {
            PageHeader(title: header.title, transitionID: header.transitionID)
                .padding(.horizontal, 20)
                .staysInPlaceWhenPulled()
        }
    }
}

// MARK: - 下拉时页头停在原位

/// 列表顶端被下拉（回弹区）的距离。单独一个可观察对象：逐帧变化只让页头重绘，不牵动整个列表。
@MainActor @Observable
final class PageHeaderPull {
    var distance: CGFloat = 0
}

extension EnvironmentValues {
    @Entry var pageHeaderPull: PageHeaderPull? = nil
}

extension View {
    /// 挂在滚动视图上：记录顶端下拉距离，交给列表里的页头。
    func tracksPageHeaderPull() -> some View { modifier(PageHeaderPullTracking()) }

    /// 挂在列表里的页头上：下拉时抵消位移，页头停在原位，只有下面的内容被拉下来（与推荐页一致）。
    /// 正常上滑不补偿，页头照常随内容离开。
    func staysInPlaceWhenPulled() -> some View { modifier(PageHeaderPullCompensation()) }
}

private struct PageHeaderPullTracking: ViewModifier {
    @State private var pull = PageHeaderPull()

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, -(geometry.contentOffset.y + geometry.contentInsets.top))
            } action: { _, distance in
                pull.distance = distance
            }
            .environment(\.pageHeaderPull, pull)
    }
}

private struct PageHeaderPullCompensation: ViewModifier {
    @Environment(\.pageHeaderPull) private var pull

    func body(content: Content) -> some View {
        content.offset(y: -(pull?.distance ?? 0))
    }
}

