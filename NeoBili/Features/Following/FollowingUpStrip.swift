import NeoBiliDomain
import SwiftUI

/// 关注页标题下方的横向头像条：「全部动态」在最前，随后是直播中和有新动态的 UP 主，
/// 末尾「全部关注」进入完整列表。轻点切换动态，再点当前 UP 主进入主页；长按直接进入直播间。
struct FollowingUpStrip: View {
    let items: [FollowingSelection]
    let selectedID: FollowingSelection.ID
    let onSelect: (FollowingSelection) -> Void
    let onOpenLive: (FollowedUp) -> Void
    let onOpenAll: () -> Void

    fileprivate static let cellWidth: CGFloat = 64

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
    }

    @ViewBuilder
    private func cell(_ item: FollowingSelection) -> some View {
        let selected = item.id == selectedID
        let select = { onSelect(item) }
        let button = Button(action: select) {
            label(title: item.id == .all ? String(localized: "全部动态") : item.title, selected: selected) {
                FollowingUpAvatar(item: item, selected: selected, size: 52)
            }
        }
        .buttonStyle(.plain)

        if let up = item.up {
            button
                .highPriorityGesture(
                    LongPressGesture(minimumDuration: 0.5, maximumDistance: 10)
                        .exclusively(before: TapGesture())
                        .onEnded { result in
                            switch result {
                            case .first(let recognized):
                                if recognized { onOpenLive(up) }
                            case .second: select()
                            }
                        }
                )
                // Expose one accessible button and wire its activation independently of touch recognition.
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .accessibilityLabel(item.title + (up.liveRoomID != nil ? String(localized: "，正在直播") : ""))
                .accessibilityHint("轻点查看动态，再次轻点进入主页；长按进入直播间")
                .accessibilityAction(.default, select)
                .accessibilityAction(named: Text("进入直播间")) { onOpenLive(up) }
                .accessibilityIdentifier("following.avatar.\(up.mid)")
        } else {
            button
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("following.avatar.all")
        }
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
            .font(.app(.caption2, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? .primary : .secondary)
            .lineLimit(1)
    }
}
