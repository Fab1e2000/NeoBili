import SwiftUI

/// 动态详情页。点文字/图文动态本身，或者点任意动态的评论按钮进来。
///
/// 上半是动态原文（作者、正文、图片或视频卡片），下半接评论区，
/// 和官方客户端的动态详情页一个结构。
struct DynamicDetailView: View {
    let entry: DynamicEntry
    /// 点赞状态直接读写所属列表的 DynamicFeedModel：详情页点完返回
    /// 列表、或在列表点完再进详情，两边看到的是同一份本地叠加状态。
    let feed: DynamicFeedModel

    @Environment(\.dismiss) private var dismiss
    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(AccountStore.self) private var account
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.videoTransitionNamespace) private var videoTransition

    @State private var comments: CommentsViewModel
    @State private var isLiking = false

    init(entry: DynamicEntry, feed: DynamicFeedModel) {
        self.entry = entry
        self.feed = feed
        _comments = State(
            initialValue: CommentsViewModel(oid: entry.commentOid, type: entry.commentType)
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                content
                actionRow

                Divider()

                Text(entry.commentCount > 0 ? "评论 \(entry.commentCount)" : "评论")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, CommentLayout.pageHorizontalInset)
                    .padding(.top, 14)
                    .padding(.bottom, 6)

                if entry.hasComments {
                    CommentsList(viewModel: comments)
                        .overlay(alignment: .top) {
                            // 评论还没回来时给个占位，别让页面下半截空着。
                            if comments.comments.isEmpty {
                                CommentsPlaceholder(viewModel: comments)
                                    .padding(.vertical, 40)
                            }
                        }
                } else {
                    ContentUnavailableView("这条动态没有评论区", systemImage: "bubble.slash")
                        .padding(.vertical, 40)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle("动态")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("关闭动态")
            }
        }
        // 详情页整屏都留给内容，底部标签栏收起来。
        .toolbarVisibility(.hidden, for: .tabBar)
        .imageViewerHost()
        .leftEdgeTapDeadZone()
        .commentComposer(viewModel: comments, enabled: entry.hasComments)
        .environment(\.commentBottomInset, 0)
        .task {
            if entry.hasComments {
                await comments.loadInitial()
            }
        }
        .onAppear {
            OrientationController.enterPortrait()
            FollowingReadStore.shared.markViewed(entry)
        }
    }

    // MARK: - 动态原文

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BiliImage(url: entry.secureAvatarURL)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.authorName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    if !entry.publishedText.isEmpty {
                        Text(entry.publishedText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, CommentLayout.pageHorizontalInset)
            .padding(.top, 12)

            if !entry.text.isEmpty {
                CommentEmoteText(
                    message: entry.text,
                    emotes: entry.emotes,
                    font: .body,
                    textStyle: .body
                )
                    // 详情页不再截断，长文也一次看完。
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, CommentLayout.pageHorizontalInset)
                    .padding(.top, 12)
            }

            if !entry.images.isEmpty {
                images
            }

            if let vote = entry.vote {
                DynamicVoteCard(vote: vote, dynamicID: entry.id)
                    .padding(.horizontal, CommentLayout.pageHorizontalInset)
                    .padding(.top, 12)
            }

            if let video = entry.video {
                videoCard(video)
            }
        }
    }

    private var images: some View {
        TappableImageGrid(dynamicImages: entry.images, cornerRadius: 6)
            .padding(.horizontal, CommentLayout.pageHorizontalInset)
            .padding(.top, 12)
    }

    private func videoCard(_ video: FollowedVideo) -> some View {
        Button {
            nowPlaying.open(
                VideoDetailRoute(
                    bvid: video.bvid,
                    cover: video.cover,
                    title: video.title,
                    artist: video.authorName
                ),
                from: video.bvid
            )
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                VideoCoverThumbnail(
                    url: video.secureCoverURL,
                    duration: video.durationText,
                    playText: video.playText,
                    cornerRadius: 6
                )

                Text(video.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, CommentLayout.pageHorizontalInset)
            .padding(.top, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .videoTransitionSource(video.bvid, in: videoTransition)
    }

    // MARK: - 转发 / 评论 / 点赞

    private var actionRow: some View {
        HStack(spacing: 0) {
            counter(icon: "arrow.2.squarepath", text: countText(entry.forwardCount, zero: "转发"))
                .frame(maxWidth: .infinity)

            counter(icon: "bubble.left", text: countText(entry.commentCount, zero: "评论"))
                .frame(maxWidth: .infinity)

            Button(action: toggleLike) {
                counter(
                    icon: feed.isLiked(entry) ? "hand.thumbsup.fill" : "hand.thumbsup",
                    text: countText(feed.likeCount(entry), zero: "点赞"),
                    isHighlighted: feed.isLiked(entry)
                )
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private func counter(icon: String, text: String, isHighlighted: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.footnote)
        .foregroundStyle(isHighlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
    }

    private func countText(_ count: Int, zero: String) -> String {
        count > 0 ? count.biliCountText : zero
    }

    private func toggleLike() {
        guard account.isLoggedIn else {
            feedback.show("请先登录")
            return
        }
        guard !isLiking else { return }

        isLiking = true
        Task { @MainActor in
            defer { isLiking = false }
            if let message = await feed.toggleLike(entry, isLoggedIn: account.isLoggedIn) {
                feedback.show(message)
            }
        }
    }
}
