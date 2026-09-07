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
                BiliImage(url: avatarURL)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            // 命中区域跟着裁成圆形，四角留白不响应点击。
            .contentShape(Circle())
            .accessibilityLabel("\(owner.name)的个人空间")

            VStack(alignment: .leading, spacing: 2) {
                Text(owner.name)
                    .font(.subheadline.weight(.medium))
                    // UP 主名字用主题色，和官方一致；这是全页唯一的彩色文字，
                    // 所以「这是个人、可以关注」这层意思不用额外图标就能读出来。
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

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
                // 未关注是实心强调色（吸引点击），已关注退成灰底描边（不再抢注意力）。
                .foregroundStyle(isFollowing ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(Color.white))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    isFollowing
                        ? AnyShapeStyle(.background.secondary)
                        : AnyShapeStyle(Color.accentColor),
                    in: Capsule()
                )
                .overlay {
                    if isFollowing {
                        Capsule().stroke(Color(uiColor: .separator), lineWidth: 0.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFollowing ? "取消关注 \(owner.name)" : "关注 \(owner.name)")
    }
}
