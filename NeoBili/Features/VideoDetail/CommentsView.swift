import SwiftUI

/// 评论页的排版参数都集中在这里。
/// 如果只想微调界面，修改下面的数字即可，不需要改程序逻辑。
private enum CommentLayout {
    /// 评论内容与屏幕左右边缘的距离。
    static let pageHorizontalInset: CGFloat = 16
    /// 每条评论上下的留白。
    static let rowVerticalPadding: CGFloat = 12
    /// 头像直径。
    static let avatarSize: CGFloat = 32
    /// 头像和右侧文字之间的距离。
    static let avatarTextSpacing: CGFloat = 10
    /// 用户名、正文、点赞行之间的竖向距离。
    static let textVerticalSpacing: CGFloat = 5
    /// 长评论收起时显示几行。想让收起状态更高或更矮，改这个数字即可。
    static let collapsedMessageLines = 6
    /// 超过这个字数才显示「展开」。太短的评论没必要多一个按钮。
    static let messageExpandThreshold = 120
    /// 楼中楼区块的圆角。
    static let replyCornerRadius: CGFloat = 8
    /// 楼中楼区块内部的留白。
    static let replyPadding: CGFloat = 8
    /// 楼中楼每条回复之间的距离。
    static let replySpacing: CGFloat = 7
}

/// 视频页的评论列表。视图模型由视频页持有，所以在简介和评论之间切换时
/// 已经加载的内容和展开状态都不会丢失。
struct CommentsView: View {
    let viewModel: CommentsViewModel
    /// 切换简介和评论时保留评论列表的滚动位置。
    @Binding var scrollPosition: ScrollPosition

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.comments) { comment in
                    CommentRow(comment: comment, viewModel: viewModel)
                        .padding(.horizontal, CommentLayout.pageHorizontalInset)
                        .padding(.vertical, CommentLayout.rowVerticalPadding)
                        .task { await viewModel.loadMoreIfNeeded(current: comment) }

                    Divider()
                        .padding(.leading, CommentLayout.pageHorizontalInset)
                }

                if viewModel.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
        }
        .scrollPosition($scrollPosition)
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            } else if let message = viewModel.errorMessage, viewModel.comments.isEmpty {
                ContentUnavailableView {
                    Label("评论加载失败", systemImage: "exclamationmark.bubble")
                } description: {
                    Text(message)
                } actions: {
                    Button("重试") {
                        Task { await viewModel.retry() }
                    }
                }
            } else if viewModel.comments.isEmpty {
                ContentUnavailableView("还没有评论", systemImage: "bubble.left")
            }
        }
        .task { await viewModel.loadInitial() }
    }
}

private struct CommentRow: View {
    let comment: Comment
    let viewModel: CommentsViewModel

    /// 正文是否已经展开。每条评论各自记住自己的状态。
    @State private var isMessageExpanded = false

    var body: some View {
        HStack(alignment: .top, spacing: CommentLayout.avatarTextSpacing) {
            BiliImage(url: comment.member.secureAvatarURL)
                .aspectRatio(contentMode: .fill)
                .frame(width: CommentLayout.avatarSize, height: CommentLayout.avatarSize)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: CommentLayout.textVerticalSpacing) {
                Text(comment.member.uname)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                messageText

                HStack(spacing: 12) {
                    Text(comment.relativeTime)
                    Label(comment.like.biliCountText, systemImage: "hand.thumbsup")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)

                if comment.rcount > 0 {
                    replySection
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - 正文展开折叠

    @ViewBuilder
    private var messageText: some View {
        Text(comment.message)
            .font(.subheadline)
            .foregroundStyle(.primary)
            .lineLimit(isMessageExpanded ? nil : CommentLayout.collapsedMessageLines)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                guard canExpandMessage else { return }
                withAnimation(.easeInOut(duration: 0.2)) { isMessageExpanded.toggle() }
            }

        if canExpandMessage {
            Button(isMessageExpanded ? "收起" : "展开") {
                withAnimation(.easeInOut(duration: 0.2)) { isMessageExpanded.toggle() }
            }
            .font(.caption.weight(.medium))
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
    }

    /// 短评论一眼就能看完，没必要多一个「展开」按钮。
    private var canExpandMessage: Bool {
        comment.message.count > CommentLayout.messageExpandThreshold
    }

    // MARK: - 楼中楼展开

    private var replySection: some View {
        let replies = viewModel.replies(for: comment)
        let isExpanded = viewModel.isExpanded(comment)

        return VStack(alignment: .leading, spacing: CommentLayout.replySpacing) {
            ForEach(replies) { reply in
                // 用户名和内容排在同一段文字里，这样回复读起来更紧凑。
                let name = Text("\(reply.member.uname)：").foregroundStyle(.secondary)
                Text("\(name)\(reply.message)")
                    .font(.caption)
                    // 收起状态下每条回复最多三行，展开后完整显示。
                    .lineLimit(isExpanded ? nil : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if viewModel.isLoadingReplies(comment) {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isExpanded, viewModel.hasMoreReplies(comment) {
                Button("加载更多回复") {
                    Task { await viewModel.loadMoreReplies(for: comment) }
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }

            // 未登录时一级评论被 B 站限制成很少几条，但楼中楼不受限制，可以完整翻页。
            if isExpanded || comment.rcount > replies.count {
                Button(isExpanded ? "收起回复" : "查看全部 \(comment.rcount.biliCountText) 条回复") {
                    Task { await viewModel.toggleReplies(for: comment) }
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CommentLayout.replyPadding)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: CommentLayout.replyCornerRadius, style: .continuous)
        )
        .padding(.top, 2)
    }
}
