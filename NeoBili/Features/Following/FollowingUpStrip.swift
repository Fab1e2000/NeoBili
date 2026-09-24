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

    private static let cellWidth: CGFloat = 64

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
        .contextMenu {
            if let up = item.up {
                if up.liveRoomID != nil {
                    Button("进入直播间", systemImage: "dot.radiowaves.left.and.right") { onOpenLive(up) }
                }
                Button("查看 UP 主主页", systemImage: "person.crop.circle") { onOpenUp(up) }
            }
        }
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
            Text(title)
                .font(.caption2.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? .primary : .secondary)
                .lineLimit(1)
        }
        .frame(width: Self.cellWidth)
        .contentShape(Rectangle())
    }
}
