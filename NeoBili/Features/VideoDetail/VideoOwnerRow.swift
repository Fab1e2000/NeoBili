import SwiftUI

/// 简介顶部的 UP 主行，平铺在页面上，不再套灰色圆角底。
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
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// 系统原生胶囊按钮：未关注是主题色醒目样式（同 App Store「获取」），已关注退为灰色。
    @ViewBuilder
    private var followButton: some View {
        let button = Button(action: onToggleFollow) {
            Text(isFollowing ? "已关注" : "关注")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 4)
        }
        .buttonBorderShape(.capsule)
        .accessibilityLabel(isFollowing ? "取消关注 \(owner.name)" : "关注 \(owner.name)")
        .accessibilityIdentifier("video.owner.follow")
        if isFollowing {
            button.buttonStyle(.bordered).tint(.secondary)
        } else {
            button.buttonStyle(.borderedProminent).tint(themeColor)
        }
    }
}
