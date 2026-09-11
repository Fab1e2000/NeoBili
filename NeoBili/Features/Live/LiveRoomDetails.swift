import SwiftUI

/// 与视频详情的名片使用相同的头像、内边距和关注按钮尺寸。
struct LiveRoomOwnerRow: View {
    let room: LiveRoom
    let card: SpaceCard?
    let isFollowing: Bool?
    let isLoading: Bool
    let isToggling: Bool
    let isOwnAccount: Bool
    let onToggleFollow: () -> Void

    private var name: String {
        if let card, !card.name.isEmpty { return card.name }
        return room.username
    }
    private var followTitle: String {
        if isOwnAccount { return "自己" }
        if room.uid <= 0 { return "加载中" }
        if isFollowing == nil { return isLoading ? "加载中" : "重试" }
        return isFollowing == true ? "已关注" : "关注"
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                BiliImage(url: card?.secureAvatarURL ?? room.faceURL)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(name.isEmpty ? "主播" : name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let card {
                        Text("\(card.follower.biliCountText)粉丝 · \(card.archiveCount)视频")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)

            Button(action: onToggleFollow) {
                Text(followTitle)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(isFollowing == true || isOwnAccount ? Color.primary : Color.white)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 36)
                    .background(isFollowing == true || isOwnAccount ? Color.primary.opacity(0.08) : Color.accentColor,
                                in: Capsule())
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(room.uid <= 0 || isOwnAccount || isToggling || isFollowing == nil && isLoading)
            .accessibilityLabel(isFollowing == true ? "取消关注 \(name)" : "\(followTitle) \(name)")
            .accessibilityIdentifier("live.owner.follow")
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule())
        .accessibilityIdentifier("live.owner")
    }
}

/// 完整标题与直播元信息共享一张玻璃卡，轻点整张卡片展开简介/公告。
struct LiveRoomIntroductionCard: View {
    let room: LiveRoom
    let isOffline: Bool
    @Binding var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .callout) private var titleLineHeight: CGFloat = 22

    private var announcement: String? { LiveRoomText.readable(room.announcement) }
    private var description: String? { LiveRoomText.readable(room.description) }
    private var hasDetails: Bool { announcement != nil || description != nil }

    var body: some View {
        if hasDetails {
            card
                .contentShape(RoundedRectangle(cornerRadius: 24))
                .onTapGesture(perform: toggleDetails)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("直播简介")
                .accessibilityValue(isExpanded ? "已展开" : "已收起")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { toggleDetails() }
                .accessibilityActions {
                    Button(isExpanded ? "收起直播简介" : "展开直播简介", action: toggleDetails)
                }
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(room.title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, hasDetails ? 36 : 0)
                .accessibilityIdentifier("live.introduction.title")
                .overlay(alignment: .topTrailing) {
                    if hasDetails {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .accessibilityHidden(true)
                            .offset(x: 8, y: (titleLineHeight - 44) / 2)
                    }
                }

            Text([
                isOffline ? "未开播" : "直播中",
                room.online > 0 ? "\(room.online.biliCountText)人气" : nil,
                room.areaName.isEmpty ? nil : room.areaName,
                "房间 \(room.roomID)"
            ].compactMap { $0 }.joined(separator: "  "))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("live.introduction.metadata")

            if isExpanded, hasDetails {
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    if let announcement {
                        detailsSection("直播公告", text: announcement)
                    }
                    if let description, description != announcement {
                        detailsSection("直播间简介", text: description)
                    }
                }
                .accessibilityIdentifier("live.introduction.description")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
    }

    private func toggleDetails() {
        guard hasDetails else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            isExpanded.toggle()
        }
    }

    private func detailsSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.medium))
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum LiveRoomText {
    static func readable(_ html: String?) -> String? {
        guard let html else { return nil }
        let text = String(html.prefix(8_000))
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
