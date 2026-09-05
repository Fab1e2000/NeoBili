import SwiftUI

/// 动态卡片的排版参数。
enum DynamicCardLayout {
    /// 卡片与屏幕左右边缘的距离。
    static let pageHorizontalInset: CGFloat = 8
    /// 上下两张卡片之间的半间距。
    static let cardVerticalSpacing: CGFloat = 4
    /// 卡片内容与卡片边缘的距离。
    static let contentInset: CGFloat = 10
    /// 卡片圆角。
    static let cardCornerRadius: CGFloat = 7
    /// 封面和图片的圆角。
    static let imageCornerRadius: CGFloat = 4
    /// UP 主头像直径。
    static let avatarSize: CGFloat = 32
    /// 九宫格图片之间的距离。
    static let gridSpacing: CGFloat = 4
    /// 正文收起时显示几行。
    static let collapsedTextLines = 6
    /// 超过这个字数才显示「展开」。太短的正文没必要多一个按钮。
    static let textExpandThreshold = 120
}

/// 关注页和 UP 主动态页共用的一张动态卡片。
///
/// 三块内容按需出现：正文、图片、视频。底部是转发数、评论、点赞。
struct DynamicCard: View {
    let entry: DynamicEntry
    let isLiked: Bool
    let likeCount: Int
    /// 点视频卡片。非视频动态不会用到。
    let onOpenVideo: () -> Void
    /// 点头像或昵称进 UP 主空间。已经在他空间里时传 nil，头像就不可点。
    let onOpenAuthor: (() -> Void)?
    let onLike: () -> Void
    /// 进动态详情页：点评论按钮，或者直接点正文、图片。
    let onOpenDetail: () -> Void

    @Environment(\.videoTransitionNamespace) private var videoTransition
    @State private var isTextExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            authorRow

            // 正文点一下进详情页看评论；「展开」按钮在它自己的范围内优先
            // 响应，所以这里用 onTapGesture 而不是再套一层 Button。
            // 图片那一块也挂着同一个手势，但每张图自己的"看大图"在内层，
            // 点到图上是看大图，点到图与图之间的空隙才是进详情。
            if !entry.text.isEmpty {
                textBlock
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onOpenDetail)
            }

            if !entry.images.isEmpty {
                imageBlock
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onOpenDetail)
            }

            if let vote = entry.vote {
                DynamicVoteCard(vote: vote, dynamicID: entry.id)
                    .padding(.horizontal, DynamicCardLayout.contentInset)
                    .padding(.top, 12)
            }

            if let video = entry.video {
                videoBlock(video)
            }

            actionBar
        }
        .background(
            RoundedRectangle(cornerRadius: DynamicCardLayout.cardCornerRadius, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: DynamicCardLayout.cardCornerRadius, style: .continuous)
                        .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 0.5)
                }
        )
    }

    // MARK: - UP 主

    private var authorRow: some View {
        Button {
            onOpenAuthor?()
        } label: {
            HStack(spacing: 8) {
                BiliImage(url: entry.secureAvatarURL)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: DynamicCardLayout.avatarSize, height: DynamicCardLayout.avatarSize)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.authorName)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !entry.publishedText.isEmpty {
                        Text(entry.publishedText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, DynamicCardLayout.contentInset)
            .padding(.top, DynamicCardLayout.contentInset)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onOpenAuthor == nil)
    }

    // MARK: - 正文

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 正文里的 [UPOWER_xxx_戳手手] 这类表情要换成图，和评论共用同一套。
            CommentEmoteText(
                message: entry.text,
                emotes: entry.emotes,
                font: .subheadline,
                textStyle: .subheadline
            )
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(isTextExpanded ? nil : DynamicCardLayout.collapsedTextLines)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 长正文才给「展开」。按字数判断，不去测量真实行数——
            // 为了一个按钮把整条动态先排一遍版不值得。
            if entry.text.count > DynamicCardLayout.textExpandThreshold {
                Button(isTextExpanded ? "收起" : "展开") {
                    withAnimation(.easeInOut(duration: 0.2)) { isTextExpanded.toggle() }
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, DynamicCardLayout.contentInset)
        .padding(.top, 8)
    }

    // MARK: - 图片

    private var imageBlock: some View {
        // 单图/九宫格的排版和"点开看大图"都在 TappableImageGrid 里，
        // 动态详情和评论配图用的是同一套。
        TappableImageGrid(
            dynamicImages: entry.images,
            spacing: DynamicCardLayout.gridSpacing,
            cornerRadius: DynamicCardLayout.imageCornerRadius
        )
        .padding(.horizontal, DynamicCardLayout.contentInset)
        .padding(.top, 8)
    }

    // MARK: - 视频

    private func videoBlock(_ video: FollowedVideo) -> some View {
        Button(action: onOpenVideo) {
            VStack(alignment: .leading, spacing: 0) {
                VideoCoverThumbnail(
                    url: video.secureCoverURL,
                    duration: video.durationText,
                    playText: video.playText,
                    cornerRadius: DynamicCardLayout.imageCornerRadius
                )

                Text(video.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 9)
            }
            .padding(.horizontal, DynamicCardLayout.contentInset)
            .padding(.top, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .videoTransitionSource(video.bvid, in: videoTransition)
    }

    // MARK: - 底部按钮

    private var actionBar: some View {
        HStack(spacing: 0) {
            // 转发只显示数字：B 站的转发要带一条自己的动态，属于发布行为，
            // 这个 App 不做发布。
            counter(icon: "arrow.2.squarepath", text: countText(entry.forwardCount, zero: "转发"))
                .frame(maxWidth: .infinity)

            Button(action: onOpenDetail) {
                counter(icon: "bubble.left", text: countText(entry.commentCount, zero: "评论"))
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!entry.hasComments)

            Button(action: onLike) {
                counter(
                    icon: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                    text: countText(likeCount, zero: "点赞"),
                    isHighlighted: isLiked
                )
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func counter(icon: String, text: String, isHighlighted: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(isHighlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
    }

    private func countText(_ count: Int, zero: String) -> String {
        count > 0 ? count.biliCountText : zero
    }
}
