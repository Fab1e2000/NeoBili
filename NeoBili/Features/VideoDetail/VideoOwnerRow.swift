import SwiftUI

/// 简介顶部的 UP 主一行：头像、名字、粉丝与投稿数，右侧是关注按钮。
///
/// 官方客户端把它放在标题**上方**，而不是像旧版这里那样夹在标题和简介之间；
/// 这样一进页面第一眼看到的是「谁发的」，和列表卡片的信息顺序也对得上。
struct VideoOwnerRow: View {
    let owner: VideoOwner
    let avatarURL: URL?
    /// 粉丝数、投稿数。名片还没回来时这一行不显示。
    let card: MemberCard?
    let isFollowing: Bool
    let onToggleFollow: () -> Void
    /// 头像是进 UP 主空间页的入口。
    let onOpenSpace: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpenSpace) {
                HStack(spacing: 10) {
                    BiliImage(url: avatarURL)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(owner.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                        if let subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(owner.name)的个人空间")

            Spacer(minLength: 8)

            followButton
        }
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
            Text(isFollowing ? "已关注" : "+ 关注")
                .font(.footnote.weight(.medium))
                .foregroundStyle(isFollowing ? Color.secondary : Color.primary)
                .padding(.horizontal, 6)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .controlSize(.regular)
        .tint(.primary)
        .accessibilityLabel(isFollowing ? "取消关注 \(owner.name)" : "关注 \(owner.name)")
    }
}
