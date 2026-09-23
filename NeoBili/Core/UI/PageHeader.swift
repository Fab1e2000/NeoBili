import SwiftUI

extension EnvironmentValues {
    /// 打开「我的」页面，参数是发起页头像的转场 ID。由根视图的 `mineSheetHost()` 提供。
    @Entry var openMine: (String) -> Void = { _ in }
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
            Button { (onOpenMine ?? { openMine(transitionID) })() } label: {
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

extension View {
    /// 在根视图上统一呈现「我的」页面，从发起页的头像原位放大。
    /// 放在根部而不是各页：隐藏某个标签时那一页会被移除，挂在它上面的卡片也会被一并关掉。
    func mineSheetHost() -> some View { modifier(MineSheetHost()) }
}

private struct MineSheetHost: ViewModifier {
    private struct Presentation: Identifiable {
        let transitionID: String
        var id: String { transitionID }
    }

    @State private var presentation: Presentation?
    @Environment(\.videoTransitionNamespace) private var transition

    func body(content: Content) -> some View {
        content
            .environment(\.openMine) { presentation = Presentation(transitionID: $0) }
            .sheet(item: $presentation) { presentation in
                MineView()
                    .appTextSize()
                    .tint(.primary)
                    .presentationDetents([.large])
                    .presentationCornerRadius(32)
                    .modifier(MineZoomTransition(transitionID: presentation.transitionID, namespace: transition))
            }
    }
}

private struct MineZoomTransition: ViewModifier {
    let transitionID: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.navigationTransition(.zoom(sourceID: transitionID, in: namespace))
        } else {
            content
        }
    }
}
