import SwiftUI

/// 关注页标题下方的横向头像条：「全部动态」在最前，随后是直播中和有新动态的 UP 主，
/// 末尾「全部关注」进入完整列表。轻点头像立即切换下方动态；长按可进主页或直播间。
struct FollowingUpStrip: View {
    let items: [FollowingSelection]
    let selectedID: FollowingSelection.ID
    let onSelect: (FollowingSelection) -> Void
    let onOpenUp: (FollowedUp) -> Void
    let onOpenLive: (FollowedUp) -> Void
    let onOpenAll: () -> Void

    fileprivate static let cellWidth: CGFloat = 64
    /// 长按预览底板的圆角，抬起过程和菜单停稳后用同一个形状。
    fileprivate static let previewCornerRadius: CGFloat = 16

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 2) {
                ForEach(items) { item in
                    cell(item)
                }
                allFollowingsCell
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("following.upStrip")
    }

    private func cell(_ item: FollowingSelection) -> some View {
        let selected = item.id == selectedID
        return Button { onSelect(item) } label: {
            label(title: item.id == .all ? String(localized: "全部动态") : item.title, selected: selected) {
                FollowingUpAvatar(item: item, selected: selected, size: 52)
            }
        }
        .buttonStyle(.plain)
        .modifier(FollowingUpContextMenu(item: item, selected: selected, onOpenUp: onOpenUp, onOpenLive: onOpenLive))
        .accessibilityLabel(item.title + (item.up?.liveRoomID != nil ? String(localized: "，正在直播") : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("following.avatar.\(item.id)")
    }

    private var allFollowingsCell: some View {
        Button(action: onOpenAll) {
            label(title: String(localized: "全部关注"), selected: false) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, height: 52)
                    .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("查看所有关注的 UP 主")
        .accessibilityIdentifier("following.allFollowings")
    }

    private func label(title: String, selected: Bool, @ViewBuilder avatar: () -> some View) -> some View {
        VStack(spacing: 4) {
            avatar()
            FollowingUpName(title: title, selected: selected)
        }
        .frame(width: Self.cellWidth)
        .contentShape(Rectangle())
    }
}

private struct FollowingUpName: View {
    let title: String
    let selected: Bool

    var body: some View {
        Text(title)
            .font(.caption2.weight(selected ? .semibold : .regular))
            .foregroundStyle(selected ? .primary : .secondary)
            .lineLimit(1)
    }
}

/// UP 主头像的长按菜单：进主页、进直播间。「全部动态」没有菜单项，不挂菜单。
///
/// 预览自己画圆角底板。头像格子本身是透明的，系统自动生成的预览只在抬起过程中
/// 临时带着底板，菜单停稳后就只剩头像和名字悬在变暗的背景上。
private struct FollowingUpContextMenu: ViewModifier {
    let item: FollowingSelection
    let selected: Bool
    let onOpenUp: (FollowedUp) -> Void
    let onOpenLive: (FollowedUp) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if let up = item.up {
            content
                .contentShape(.contextMenuPreview,
                              RoundedRectangle(cornerRadius: FollowingUpStrip.previewCornerRadius, style: .continuous))
                .contextMenu {
                    if up.liveRoomID != nil {
                        Button("进入直播间", systemImage: "dot.radiowaves.left.and.right") { onOpenLive(up) }
                    }
                    Button("查看 UP 主主页", systemImage: "person.crop.circle") { onOpenUp(up) }
                } preview: {
                    FollowingUpPreview(item: item, selected: selected)
                }
        } else {
            content
        }
    }
}

/// 长按时菜单旁的预览：和头像条里的格子一样，只是名字不截断，并带上圆角底板。
private struct FollowingUpPreview: View {
    let item: FollowingSelection
    let selected: Bool

    var body: some View {
        VStack(spacing: 4) {
            FollowingUpAvatar(item: item, selected: selected, size: 52)
            FollowingUpName(title: item.title, selected: selected)
                .frame(maxWidth: 220)
        }
        .frame(minWidth: FollowingUpStrip.cellWidth)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: FollowingUpStrip.previewCornerRadius, style: .continuous))
        // 预览由单独的宿主呈现，文字档位和主题色在这里重新注入。
        .appTextSize()
    }
}
