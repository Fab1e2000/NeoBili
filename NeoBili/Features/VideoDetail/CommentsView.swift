import SwiftUI

/// 评论页的排版参数都集中在这里。
/// 如果只想微调界面，修改下面的数字即可，不需要改程序逻辑。
enum CommentLayout {
    /// 评论内容与屏幕左右边缘的距离。
    static let pageHorizontalInset: CGFloat = 16
    /// 每条评论上下的留白，也就是内容到分隔线的距离。
    static let rowVerticalPadding: CGFloat = 12
    /// 头像直径。
    static let avatarSize: CGFloat = 32
    /// 头像和右侧文字之间的距离。
    static let avatarTextSpacing: CGFloat = 10
    /// 用户名、正文、点赞行之间的竖向距离。
    static let textVerticalSpacing: CGFloat = 5
    /// 楼中楼区块与上方点赞行之间的距离。
    static let replyBlockGap: CGFloat = 12
    /// 楼中楼区块的圆角。
    static let replyCornerRadius: CGFloat = 8
    /// 楼中楼区块内部的留白。
    static let replyPadding: CGFloat = 10
    /// 楼中楼每条回复之间的距离。
    static let replySpacing: CGFloat = 7
    /// 长评论收起时显示几行。想让收起状态更高或更矮，改这个数字即可。
    static let collapsedMessageLines = 6
    /// 超过这个字数才显示「展开」。太短的评论没必要多一个按钮。
    static let messageExpandThreshold = 120
}

/// 评论列表本体（没有自己的 ScrollView）。
///
/// 视频页把它放进 `CommentsView` 的滚动容器里；动态详情页要在同一个滚动区
/// 里先放动态内容再接评论，所以需要这层不带容器的版本——两个 ScrollView
/// 套在一起没法正常滚动。
struct CommentsList: View {
    let viewModel: CommentsViewModel
    @Environment(ActionFeedback.self) private var feedback

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(viewModel.comments) { comment in
                CommentRow(comment: comment, viewModel: viewModel)
                    .padding(.horizontal, CommentLayout.pageHorizontalInset)
                    .padding(.vertical, CommentLayout.rowVerticalPadding)
                    .task { await viewModel.loadMoreIfNeeded(current: comment) }

                // 最后一条下面不画线：列表末尾悬着一根分隔线看起来像还没加载完。
                if comment.id != viewModel.comments.last?.id {
                    Divider()
                        .padding(.leading, CommentLayout.pageHorizontalInset)
                }
            }

            if viewModel.isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
        // 和视频页一样走非模态浮层，别用 alert 去和 fullScreenCover 抢 present。
        .onChange(of: viewModel.actionMessage) { _, message in
            guard let message else { return }
            feedback.show(message)
            viewModel.actionMessage = nil
        }
    }
}

/// 视频页的评论列表。视图模型由视频页持有，所以在简介和评论之间切换时
/// 已经加载的内容和展开状态都不会丢失。
struct CommentsView: View {
    let viewModel: CommentsViewModel
    /// 切换简介和评论时保留评论列表的滚动位置。
    @Binding var scrollPosition: ScrollPosition

    var body: some View {
        ScrollView {
            CommentsList(viewModel: viewModel)
        }
        .scrollPosition($scrollPosition)
        .overlay {
            CommentsPlaceholder(viewModel: viewModel)
        }
        .task { await viewModel.loadInitial() }
    }
}

/// 加载中 / 失败 / 空评论三种占位，两个页面共用。
struct CommentsPlaceholder: View {
    let viewModel: CommentsViewModel

    var body: some View {
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
}

/// 单条评论。`internal` 而不是 `private`，因为楼中楼那块的上下间距要靠
/// `CommentSpacingTests` 渲染出来实测——这处间距已经错过两回，靠读代码判断不可靠。
struct CommentRow: View {
    let comment: Comment
    let viewModel: CommentsViewModel

    @Environment(AccountStore.self) private var account

    /// 正文是否已经展开。每条评论各自记住自己的状态。
    @State private var isMessageExpanded = false

    var body: some View {
        HStack(alignment: .top, spacing: CommentLayout.avatarTextSpacing) {
            BiliImage(url: comment.member.secureAvatarURL)
                .aspectRatio(contentMode: .fill)
                .frame(width: CommentLayout.avatarSize, height: CommentLayout.avatarSize)
                .clipShape(Circle())

            // 每一段的间距在这里逐个写明，而不是靠 VStack 的统一 spacing 再叠
            // 局部 padding——楼中楼那块需要和分隔线保持等距，混着两种来源
            // 就会出现「上紧下松」的不一致。
            VStack(alignment: .leading, spacing: 0) {
                Text(comment.member.uname)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                messageText
                    .padding(.top, CommentLayout.textVerticalSpacing)

                if !comment.pictures.isEmpty {
                    // 配图不占满整行：评论正文本来就有头像的缩进，
                    // 图再铺满会显得比正文还宽。
                    TappableImageGrid(commentPictures: comment.pictures)
                        .padding(.trailing, CommentLayout.pageHorizontalInset)
                        .padding(.top, CommentLayout.textVerticalSpacing)
                }

                metaRow
                    .padding(.top, CommentLayout.textVerticalSpacing)

                if comment.rcount > 0 {
                    replySection
                        .padding(.top, CommentLayout.replyBlockGap)
                }
            }

            Spacer(minLength: 0)
        }
        // 横向分页容器会向评论页传入整屏高度；明确按内容固有高度收紧，
        // 避免带楼中楼的评论行吞掉剩余空间，把分隔线推到很远的位置。
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 时间 + 点赞按钮那一行。
    private var metaRow: some View {
        HStack(spacing: 12) {
            Text(comment.relativeTime)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            likeButton
        }
    }

    private var likeButton: some View {
        let isLiked = viewModel.isLiked(comment)
        let count = viewModel.likeCount(comment)

        return Button {
            Task { await viewModel.toggleLike(comment, isLoggedIn: account.isLoggedIn) }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "hand.thumbsup")
                    .symbolVariant(isLiked ? .fill : .none)
                Text(count > 0 ? count.biliCountText : "赞")
            }
            .font(.caption2)
            .foregroundStyle(isLiked ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
            // 图标本身很小，扩一圈点击区域，免得点不中。
            .padding(.vertical, 3)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLiked ? "取消点赞" : "点赞")
        .accessibilityValue("\(count)")
        .accessibilityAddTraits(isLiked ? [.isSelected] : [])
    }

    // MARK: - 正文展开折叠

    /// 正文和「展开」按钮。
    ///
    /// 以前这里是个返回两个视图的 ViewBuilder，交给外层 VStack 去排；现在收成
    /// 一个 VStack，外层每一段的间距才能一眼看清。
    private var messageText: some View {
        VStack(alignment: .leading, spacing: CommentLayout.textVerticalSpacing) {
            CommentEmoteText(
                message: comment.message,
                emotes: comment.emotes,
                font: .subheadline,
                textStyle: .subheadline
            )
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
                // 用户名单独作为一段前缀交给同一个渲染器，表情才能和文字排在一行。
                CommentEmoteText(
                    message: reply.message,
                    emotes: reply.emotes,
                    font: .caption,
                    textStyle: .caption,
                    prefix: "\(reply.member.uname)："
                )
                    // 楼中楼只折叠回复数量，不截断单条正文，也不预留隐藏行高度。
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .task(id: isExpanded && reply.id == replies.last?.id && viewModel.hasMoreReplies(comment)) {
                        if isExpanded, reply.id == replies.last?.id, viewModel.hasMoreReplies(comment) {
                            await viewModel.loadMoreReplies(for: comment)
                        }
                    }
            }

            if viewModel.isLoadingReplies(comment) {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let error = viewModel.replyErrors[comment.id] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.shouldShowAllReplies(comment) {
                Button("查看全部回复") {
                    Task { await viewModel.expandReplies(for: comment) }
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(viewModel.isLoadingReplies(comment))
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(CommentLayout.replyPadding)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: CommentLayout.replyCornerRadius, style: .continuous)
        )
    }
}
