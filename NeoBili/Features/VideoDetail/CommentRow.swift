#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI

/// 单条评论。`internal` 而不是 `private`，因为楼中楼那块的上下间距要靠
/// `CommentSpacingTests` 渲染出来实测——这处间距已经错过两回，靠读代码判断不可靠。
struct CommentRow: View {
    let comment: Comment
    let viewModel: CommentsViewModel
    /// 楼中楼那一块要不要画。单独页面里根评论和回复都不需要，它下面接的
    /// 就是全部回复，再画一块会套娃。
    var showsReplies = true
    var root: Comment? = nil
    @Environment(\.openCommentAuthor) private var openAuthor
    @Environment(\.appThemeColor) private var themeColor

    var body: some View {
        HStack(alignment: .top, spacing: CommentLayout.avatarTextSpacing) {
            authorLink {
                BiliImage(url: comment.member.secureAvatarURL,
                      targetSize: CGSize(width: CommentLayout.avatarSize, height: CommentLayout.avatarSize))
                .aspectRatio(contentMode: .fill)
                .frame(width: CommentLayout.avatarSize, height: CommentLayout.avatarSize)
                .clipShape(Circle())
            }

            // 每一段的间距在这里逐个写明，而不是靠 VStack 的统一 spacing 再叠
            // 局部 padding——楼中楼那块需要和分隔线保持等距，混着两种来源
            // 就会出现「上紧下松」的不一致。
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    authorLink {
                        Text(comment.member.uname)
                            .font(.app(.footnote, weight: .semibold))
                            .foregroundStyle(.primary.opacity(CommentLayout.emphasisOpacity))
                            .lineLimit(1)
                    }
                    if viewModel.isUploader(comment) { CommentUPBadge().layoutPriority(1) }
                    Spacer(minLength: 0)
                }

                if viewModel.isPinned(comment) {
                    Label("置顶", systemImage: "pin.fill")
                        .font(.app(.caption2, weight: .medium)).foregroundStyle(themeColor)
                        .padding(.top, CommentLayout.nameMessageSpacing)
                }

                ExpandableCommentMessage(comment: comment)
                    .padding(.top, CommentLayout.nameMessageSpacing)
                    .contentShape(Rectangle())
                    .commentActions(comment: comment, root: root, viewModel: viewModel)

                if !comment.pictures.isEmpty {
                    // 配图不占满整行：评论正文本来就有头像的缩进，
                    // 图再铺满会显得比正文还宽。
                    TappableImageGrid(commentPictures: comment.pictures)
                        .padding(.trailing, CommentLayout.pageHorizontalInset)
                        .padding(.top, CommentLayout.textVerticalSpacing)
                }

                if comment.upAction?.like == true || comment.upAction?.reply == true {
                    CommentUPInteraction(comment: comment).padding(.top, 6)
                }

                CommentMetaRow(comment: comment, viewModel: viewModel)
                    .padding(.top, CommentLayout.actionRowGap)

                if showsReplies {
                    CommentReplyPreview(comment: comment, viewModel: viewModel)
                }
            }

            Spacer(minLength: 0)
        }
        // 横向分页容器会向评论页传入整屏高度；明确按内容固有高度收紧，
        // 避免带楼中楼的评论行吞掉剩余空间，把分隔线推到很远的位置。
        .fixedSize(horizontal: false, vertical: true)
        .opacity(viewModel.deletingIDs.contains(comment.id) ? 0.5 : 1)
        .disabled(viewModel.deletingIDs.contains(comment.id))
        .accessibilityIdentifier("comment.row.\(comment.id)")
    }

    @ViewBuilder private func authorLink<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if comment.authorID != nil {
            Button { openAuthor?(comment.member) } label: { content() }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "查看\(comment.member.uname)的主页"))
        } else { content() }
    }

}

private struct CommentMetaRow: View {
    let comment: Comment
    let viewModel: CommentsViewModel
    @Environment(\.replyToComment) private var replyToComment

    /// 时间 + 点赞按钮那一行。
    var body: some View {
        HStack(spacing: 12) {
            // 和点赞、回复并排时只占一行；放不下（大字号）就从末尾省略，不折行把按钮挤开。
            Text([comment.relativeTime, comment.location].compactMap { $0 }.joined(separator: " · "))
                .font(.app(.caption))
                .foregroundStyle(.primary.opacity(CommentLayout.metadataOpacity))
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 8) {
                CommentLikeButton(comment: comment, viewModel: viewModel)
                if let replyToComment {
                    Button { replyToComment(comment) } label: {
                        CommentActionLabel(title: String(localized: "回复"), symbol: "arrowshape.turn.up.left")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("回复评论")
                }
            }
        }
    }

}

private struct CommentLikeButton: View {
    let comment: Comment
    let viewModel: CommentsViewModel
    @Environment(AccountStore.self) private var account

    var body: some View {
        let isLiked = viewModel.isLiked(comment)
        let count = viewModel.likeCount(comment)

        return Button {
            Task { await viewModel.toggleLike(comment, isLoggedIn: account.isLoggedIn) }
        } label: {
            CommentActionLabel(title: count > 0 ? count.biliCountText : String(localized: "赞"),
                                    symbol: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                                    isSelected: isLiked)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLiked ? "取消点赞" : "点赞")
        .accessibilityValue("\(count)")
        .accessibilityAddTraits(isLiked ? [.isSelected] : [])
    }

}

/// 高度变化和展开状态只更新正文，不重建头像、操作行或楼中楼。
struct ExpandableCommentMessage: View {
    let comment: Comment
    @State private var isMessageExpanded = false
    @State private var overflowMessageHeight: CGFloat = 0
    @State private var collapsedMessageHeight: CGFloat = 0

    // MARK: - 正文展开折叠

    /// 正文和「展开」按钮。
    ///
    /// 以前这里是个返回两个视图的 ViewBuilder，交给外层 VStack 去排；现在收成
    /// 一个 VStack，外层每一段的间距才能一眼看清。
    var body: some View {
        VStack(alignment: .leading, spacing: CommentLayout.textVerticalSpacing) {
            messageBody
                .foregroundStyle(.primary)
                .lineLimit(isMessageExpanded ? nil : CommentLayout.collapsedMessageLines)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    if !isMessageExpanded { collapsedMessageHeight = $0 }
                }
                .background { messageMeasurements }
                .frame(maxWidth: .infinity, alignment: .leading)

            if canExpandMessage {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isMessageExpanded.toggle() }
                } label: {
                    Text(isMessageExpanded ? "收起" : "展开")
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(isMessageExpanded ? "收起评论正文" : "展开评论正文")
                .font(.app(.caption, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }
        }
    }

    private var messageBody: some View {
        CommentEmoteText(message: comment.message, emotes: comment.emotes,
                         font: .app(.subheadline), textStyle: .subheadline, jumpURLs: comment.content.jumpURLs)
    }

    private var measuredMessageBody: some View {
        CommentEmoteText(message: comment.message, emotes: comment.emotes,
                         font: .app(.subheadline), textStyle: .subheadline, jumpURLs: comment.content.jumpURLs, loadsEmotes: false)
    }

    /// 只比较六行和七行即可知道是否溢出，不为收起的长文排版全部内容。
    private var messageMeasurements: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // 收起时直接使用可见正文的高度，避免每条评论再排一份六行正文。
                // 展开后才补这个探针，字号或宽度变化时仍能正确判断能否收起。
                if isMessageExpanded {
                    measuredMessageBody
                        .lineLimit(CommentLayout.collapsedMessageLines)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: geometry.size.width, alignment: .leading)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            collapsedMessageHeight = $0
                        }
                }
                measuredMessageBody
                    .lineLimit(CommentLayout.collapsedMessageLines + 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: geometry.size.width, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        overflowMessageHeight = $0
                    }
            }
            .hidden()
            .accessibilityHidden(true)
            .allowsHitTesting(false)
        }
    }

    private var canExpandMessage: Bool {
        collapsedMessageHeight > 0 && overflowMessageHeight > collapsedMessageHeight + 0.5
    }

}

private struct CommentReplyPreview: View {
    let comment: Comment
    let viewModel: CommentsViewModel
    @Environment(\.openCommentThread) private var openCommentThread

    var body: some View {
        if viewModel.replyCount(for: comment) > 0 {
            replySection.padding(.top, CommentLayout.replyBlockGap)
        }
    }

    // MARK: - 楼中楼预览

    private var replySection: some View {
        let replies = viewModel.replies(for: comment)

        return VStack(alignment: .leading, spacing: CommentLayout.replySpacing) {
            ForEach(replies) { reply in
                // 用户名和内容排在同一段文字里，这样回复读起来更紧凑。
                // 用户名单独作为一段前缀交给同一个渲染器，表情才能和文字排在一行。
                CommentPreviewMessage(reply: reply, root: comment, viewModel: viewModel)
                    // 楼中楼只折叠回复数量，不截断单条正文，也不预留隐藏行高度。
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if viewModel.isLoadingReplies(comment) {
                LoadingTaskAnchor()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let error = viewModel.replyErrors[comment.id] {
                Text(error)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }

            if viewModel.shouldShowAllReplies(comment) {
                Button { openCommentThread(comment) } label: {
                    HStack(spacing: 2) {
                        Text("查看全部 \(viewModel.replyCount(for: comment)) 条回复")
                        Image(systemName: "chevron.right")
                            .imageScale(.small)
                            .accessibilityHidden(true)
                    }
                }
                .font(.app(.footnote, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
#if NEOBILI_REGRESSION
        .anchorPreference(key: CommentReplyLayoutBoundsKey.self, value: .bounds) { [.content: $0] }
#endif
        .padding(.horizontal, CommentLayout.replyHorizontalPadding)
        .padding(.vertical, CommentLayout.replyVerticalPadding)
        .background(
            Color(uiColor: .secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: CommentLayout.replyCornerRadius, style: .continuous)
        )
#if NEOBILI_REGRESSION
        .transformAnchorPreference(key: CommentReplyLayoutBoundsKey.self, value: .bounds) { values, anchor in
            values[.block] = anchor
        }
#endif
    }
}

private struct CommentPreviewMessage: View {
    let reply: Comment
    let root: Comment
    let viewModel: CommentsViewModel
    @Environment(\.openCommentAuthor) private var openAuthor
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var size
    @Environment(\.displayScale) private var scale
    @Environment(\.appThemeColor) private var color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        CommentEmoteText(message: reply.message, emotes: reply.emotes, font: .app(.footnote), textStyle: .footnote,
            prefix: reply.member.uname,
            prefixURL: reply.authorID.flatMap { URL(string: "neobili://comment-author/\($0)") },
            prefixStyle: .init(weight: .semibold, opacity: CommentLayout.emphasisOpacity),
            prefixBadge: viewModel.isUploader(reply) ? CommentUPBadge.inlineImage(size: size, scale: scale, color: color, scheme: scheme) : nil,
            prefixSuffix: "：", jumpURLs: reply.content.jumpURLs)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "neobili", url.host == "comment-author" { openAuthor?(reply.member) }
                else { openURL(url) }
                return .handled
            })
            .contentShape(Rectangle())
            .commentActions(comment: reply, root: root, viewModel: viewModel)
            .disabled(viewModel.deletingIDs.contains(reply.id))
            .opacity(viewModel.deletingIDs.contains(reply.id) ? 0.5 : 1)
            .accessibilityIdentifier("comment.preview.\(reply.id)")
    }
}

/// 紧凑的普通图文按钮，整块留白都可点击。
struct CommentActionLabel: View {
    let title: String
    let symbol: String
    var isSelected = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(title)
        }
        .font(.app(.caption, weight: isSelected ? .semibold : nil))
        .foregroundStyle(.primary.opacity(isSelected ? 1 : CommentLayout.emphasisOpacity))
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 8)
        .frame(minWidth: 44, minHeight: 32)
        .contentShape(Rectangle())
    }
}
