import SwiftUI

/// Profile presentation; follow actions and scroll coordination remain with the page.
struct SpaceProfileHeader<FollowButton: View>: View {
    let card: SpaceCard?
    let up: FollowedUp
    let themeColor: Color
    @ViewBuilder let followButton: FollowButton
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            banner

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(card?.name ?? up.uname)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)

                    if let level = card?.level, level > 0 {
                        Text("LV\(level)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(themeColor, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }

                    if card?.isVIP == true {
                        Text("大会员")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.pink, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }

                    Spacer(minLength: 0)

                    followButton
                }

                statsRow

                if let sign = card?.sign, !sign.isEmpty {
                    Text(sign)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, SpaceHeaderLayout.horizontalInset)
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
    }

    /// 头图。头像压在它的左下角，一半探出到下面的信息区里。
    private var banner: some View {
        Group {
            if let url = card?.bannerURL(isDark: colorScheme == .dark) {
                CoverThumbnail(url: url, aspectRatio: SpaceHeaderLayout.bannerAspectRatio)
            } else {
                // 没设置过头图（或者名片还没回来）时给一层渐变，
                // 比让图片控件显示「图裂了」的占位好看得多。
                LinearGradient(
                    colors: [themeColor.opacity(0.55), themeColor.opacity(0.15)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .aspectRatio(SpaceHeaderLayout.bannerAspectRatio, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            BiliImage(url: card?.secureAvatarURL ?? up.secureAvatarURL)
                .aspectRatio(contentMode: .fill)
                .frame(width: SpaceHeaderLayout.avatarSize, height: SpaceHeaderLayout.avatarSize)
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(Color(uiColor: .secondarySystemGroupedBackground), lineWidth: 3)
                }
                // 头像不要顶在屏幕左缘，和下面的名字、签名对齐。
                .padding(.leading, SpaceHeaderLayout.horizontalInset)
                .offset(y: SpaceHeaderLayout.avatarSize / 2)
        }
        // 给探出来的那半个头像让出高度。
        .padding(.bottom, SpaceHeaderLayout.avatarSize / 2 + 8)
    }

    private var statsRow: some View {
        HStack(spacing: 22) {
            stat(count: card?.follower, label: String(localized: "粉丝"))
            stat(count: card?.followingCount, label: String(localized: "关注"))
            stat(count: card?.likeCount, label: String(localized: "获赞"))
            Spacer(minLength: 0)
        }
    }

    private func stat(count: Int?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(count.map(\.biliCountText) ?? "—")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

}
