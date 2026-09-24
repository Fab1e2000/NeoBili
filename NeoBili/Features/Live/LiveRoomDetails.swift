import SwiftUI

/// 与视频详情共用独立容器的主播信息。
struct LiveRoomOwnerRow: View {
    @Environment(\.appThemeColor) private var themeColor
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
        if isOwnAccount { return String(localized: "自己") }
        if room.uid <= 0 { return String(localized: "加载中") }
        if isFollowing == nil { return isLoading ? String(localized: "加载中") : String(localized: "重试") }
        return isFollowing == true ? String(localized: "已关注") : String(localized: "follow.action", defaultValue: "关注")
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                BiliImage(url: card?.secureAvatarURL ?? room.faceURL)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(name.isEmpty ? String(localized: "主播") : name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let card {
                        Text(String(localized: "\(card.follower.biliCountText)粉丝 · \(card.archiveCount)视频"))
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
                    .background(isFollowing == true || isOwnAccount ? Color(uiColor: .tertiarySystemFill) : themeColor,
                                in: Capsule())
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(room.uid <= 0 || isOwnAccount || isToggling || isFollowing == nil && isLoading)
            .accessibilityLabel(isFollowing == true ? "取消关注 \(name)" : "\(followTitle) \(name)")
            .accessibilityIdentifier("live.owner.follow")
        }
        .mediaDetailContainer()
        .accessibilityIdentifier("live.owner")
    }
}

/// 标题与直播元信息的独立容器，轻点展开简介/公告。
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
                .contentShape(Rectangle())
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
                .padding(.trailing, hasDetails ? 24 : 0)
                .accessibilityIdentifier("live.introduction.title")
                .overlay(alignment: .topTrailing) {
                    if hasDetails {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(height: titleLineHeight)
                            .accessibilityHidden(true)
                    }
                }

            Text([
                isOffline ? String(localized: "未开播") : String(localized: "直播中"),
                room.online > 0 ? String(localized: "\(room.online.biliCountText)人气") : nil,
                room.areaName.isEmpty ? nil : room.areaName,
                String(localized: "房间 \(room.roomID)")
            ].compactMap { $0 }.joined(separator: "  "))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("live.introduction.metadata")

            if isExpanded, hasDetails {
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    if let announcement {
                        detailsSection(String(localized: "直播公告"), text: announcement)
                    }
                    if let description, description != announcement {
                        detailsSection(String(localized: "直播间简介"), text: description)
                    }
                }
                .accessibilityIdentifier("live.introduction.description")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .mediaDetailContainer()
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
