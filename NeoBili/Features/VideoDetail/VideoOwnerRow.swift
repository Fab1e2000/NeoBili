import SwiftUI

/// 简介顶部独立容器中的 UP 主行。
struct VideoOwnerRow: View {
    @Environment(\.appThemeColor) private var themeColor
    let owner: VideoOwner
    let avatarURL: URL?
    /// 粉丝数、投稿数。名片还没回来时这一行不显示。
    let card: MemberCard?
    let isFollowing: Bool
    let onToggleFollow: () -> Void
    /// 头像是进 UP 主空间页的入口。
    let onOpenSpace: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpenSpace) {
                HStack(spacing: 10) {
                    BiliImage(url: avatarURL)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(owner.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if let subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(owner.name)的个人空间")
            .accessibilityValue(subtitle ?? "")
            .accessibilityIdentifier("video.owner.open")

            followButton
        }
        .mediaDetailContainer()
    }

    private var subtitle: String? {
        var parts: [String] = []
        if let follower = card?.follower {
            parts.append("\(follower.biliCountText)粉丝")
        }
        if let archiveCount = card?.archiveCount {
            parts.append("\(archiveCount)视频")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var followButton: some View {
        Button(action: onToggleFollow) {
            Text(isFollowing ? "已关注" : "关注")
                .font(.footnote.weight(.medium))
                .foregroundStyle(isFollowing ? Color.primary : Color.white)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 16)
                .frame(minHeight: 36)
                .background(isFollowing ? Color(uiColor: .tertiarySystemFill) : themeColor, in: Capsule())
                .frame(minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFollowing ? "取消关注 \(owner.name)" : "关注 \(owner.name)")
        .accessibilityIdentifier("video.owner.follow")
    }
}
