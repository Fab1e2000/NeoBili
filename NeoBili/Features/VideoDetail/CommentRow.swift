import NeoBiliDomain
import SwiftUI

/// 单条评论。显示输入是父级一次求值得到的快照，行内不再观察评论模型；
/// 输入不变时 `Equatable` 让 SwiftUI 跳过整行重建。
struct CommentRow: View, Equatable {
    let model: CommentRowModel
    let actions: CommentRowActions

    nonisolated static func == (lhs: CommentRow, rhs: CommentRow) -> Bool { lhs.model == rhs.model }

    @Environment(\.openCommentAuthor) private var openAuthor
    @Environment(\.appThemeColor) private var themeColor

    var body: some View {
        let comment = model.comment
        HStack(alignment: .top, spacing: CommentLayout.avatarTextSpacing) {
            authorLink(for: comment) {
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
                    authorLink(for: comment) {
                        Text(comment.member.uname)
                            .font(.app(.footnote, weight: .semibold))
                            .foregroundStyle(.primary.opacity(CommentLayout.emphasisOpacity))
                            .lineLimit(1)
                    }
                    if model.isUploader { CommentUPBadge().layoutPriority(1) }
                    Spacer(minLength: 0)
                }

                if model.isPinned {
                    Label("置顶", systemImage: "pin.fill")
                        .font(.app(.caption2, weight: .medium)).foregroundStyle(themeColor)
                        .padding(.top, CommentLayout.nameMessageSpacing)
                }

                ExpandableCommentMessage(comment: comment, isExpanded: model.isExpanded) {
                    actions.toggleExpansion(comment)
                }
                    .commentActions(comment: comment, root: model.root, surface: .systemBackground,
                                    isDeleting: model.isDeleting)
                    .padding(.top, CommentLayout.nameMessageSpacing)

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

                CommentMetaRow(comment: comment, isLiked: model.isLiked,
                               likeCount: model.likeCount, actions: actions)
                    .padding(.top, CommentLayout.actionRowGap)

                if model.showsReplies {
                    CommentReplyPreview(comment: comment, model: model)
                }
            }

            Spacer(minLength: 0)
        }
        // 横向分页容器会向评论页传入整屏高度；明确按内容固有高度收紧，
        // 避免带楼中楼的评论行吞掉剩余空间，把分隔线推到很远的位置。
        .fixedSize(horizontal: false, vertical: true)
        .opacity(model.isDeleting ? 0.5 : 1)
        .disabled(model.isDeleting)
        .accessibilityIdentifier("comment.row.\(comment.id)")
    }

    @ViewBuilder private func authorLink<Content: View>(for comment: Comment,
                                                        @ViewBuilder content: () -> Content) -> some View {
        if comment.authorID != nil {
            Button { openAuthor?(comment.member) } label: { content() }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "查看\(comment.member.uname)的主页"))
        } else { content() }
    }

}

private struct CommentMetaRow: View {
    let comment: Comment
    let isLiked: Bool
    let likeCount: Int
    let actions: CommentRowActions
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
                CommentLikeButton(comment: comment, isLiked: isLiked,
                                  likeCount: likeCount, actions: actions)
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
    let isLiked: Bool
    let likeCount: Int
    let actions: CommentRowActions
    @Environment(AccountStore.self) private var account

    var body: some View {
        Button {
            actions.toggleLike(comment, isLoggedIn: account.isLoggedIn)
        } label: {
            CommentActionLabel(title: likeCount > 0 ? likeCount.biliCountText : String(localized: "赞"),
                                    symbol: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                                    isSelected: isLiked)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLiked ? "取消点赞" : "点赞")
        .accessibilityValue("\(likeCount)")
        .accessibilityAddTraits(isLiked ? [.isSelected] : [])
    }

}

/// 根据父布局给出的宽度直接确定正文与按钮的位置。
struct ExpandableCommentMessage: View {
    let comment: Comment
    /// 展开状态由评论模型持有；列表宿主复用或行重配时不会丢失。
    let isExpanded: Bool
    let onToggle: () -> Void
    @Environment(\.dynamicTypeSize) private var size
    @Environment(\.displayScale) private var scale
    @Environment(\.commentTimeJump) private var timeJump
    @Environment(\.locale) private var locale
    @Environment(\.layoutDirection) private var direction
    @Environment(\.legibilityWeight) private var legibility

    var body: some View {
        let metrics = CommentMessageMetrics(message: comment.message, emotes: comment.emotes,
            links: comment.content.jumpURLs, size: size, scale: scale,
            includesTimes: timeJump != nil, bold: legibility == .bold, locale: locale, direction: direction)
        CommentMessageLayout(metrics: metrics, expanded: isExpanded) {
            CommentEmoteText(message: comment.message, emotes: comment.emotes,
                             font: .app(.subheadline), textStyle: .subheadline, jumpURLs: comment.content.jumpURLs)
                .foregroundStyle(.primary)
                .lineLimit(isExpanded ? nil : CommentLayout.collapsedMessageLines)
                .fixedSize(horizontal: false, vertical: true)
            GeometryReader { slot in
                if slot.size.height > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { onToggle() }
                    } label: {
                        Text(isExpanded ? "收起" : "展开")
                            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(isExpanded ? "收起评论正文" : "展开评论正文")
                    .font(.app(.caption, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
            }
        }
    }
}

/// Measure the visible Text at its actual proposal. Only the button consumes
/// additional space, and its zero-height proposal removes its accessibility node.
private struct CommentMessageLayout: Layout {
    let metrics: CommentMessageMetrics
    let expanded: Bool

    private func dimensions(width: CGFloat, subviews: Subviews) -> (body: CGFloat, button: CGFloat) {
        let body = metrics.bodyHeight(width: width, expanded: expanded) {
            subviews[0].sizeThatFits(.init(width: width, height: nil)).height
        }
        let button: CGFloat = metrics.canExpand(at: width) ? max(44, metrics.buttonHeight) : 0
        return (body, button)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? subviews[0].sizeThatFits(.unspecified).width
        let d = dimensions(width: width, subviews: subviews)
        return CGSize(width: width, height: d.body + d.button + (d.button > 0 ? CommentLayout.textVerticalSpacing : 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let d = dimensions(width: bounds.width, subviews: subviews)
        subviews[0].place(at: bounds.origin, proposal: .init(width: bounds.width, height: d.body))
        subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.maxY - d.button),
                          proposal: .init(width: bounds.width, height: d.button))
    }
}

private struct CommentReplyPreview: View {
    let comment: Comment
    let model: CommentRowModel
    @Environment(\.openCommentThread) private var openCommentThread
    @Environment(\.removalFillTracksIdentity) private var tracksIdentity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.commentCardAnimations) private var cardAnimations

    private var animatesPreviewRemoval: Bool { tracksIdentity && cardAnimations && !reduceMotion }

    var body: some View {
        Group {
            if model.replyCount > 0 {
                replySection
                    .padding(.top, CommentLayout.replyBlockGap)
                    .removalFillTransition()
            }
        }
        .removalFill(ids: model.previewReplies.map(\.comment.id), enabled: animatesPreviewRemoval)
    }

    // MARK: - 楼中楼预览

    private var replySection: some View {
        VStack(alignment: .leading, spacing: CommentLayout.replySpacing) {
            ForEach(model.previewReplies, id: \.comment.id) { reply in
                // 用户名和内容排在同一段文字里，这样回复读起来更紧凑。
                // 用户名单独作为一段前缀交给同一个渲染器，表情才能和文字排在一行。
                CommentPreviewMessage(reply: reply, root: comment)
                    .removalFillTransition()
                    // 楼中楼只折叠回复数量，不截断单条正文，也不预留隐藏行高度。
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.showsAllReplies {
                Button { openCommentThread(comment) } label: {
                    HStack(spacing: 2) {
                        Text("查看全部 \(model.replyCount) 条回复")
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

struct CommentPreviewMessage: View {
    let reply: CommentRowModel.Reply
    let root: Comment
    @Environment(\.openCommentAuthor) private var openAuthor
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var size
    @Environment(\.displayScale) private var scale
    @Environment(\.appThemeColor) private var color
    @Environment(\.colorScheme) private var scheme

    private var comment: Comment { reply.comment }

    var body: some View {
        CommentEmoteText(message: comment.message, emotes: comment.emotes, font: .app(.footnote), textStyle: .footnote,
            prefix: comment.member.uname,
            prefixURL: comment.authorID.flatMap { URL(string: "neobili://comment-author/\($0)") },
            prefixStyle: .init(weight: .semibold, opacity: CommentLayout.emphasisOpacity),
            prefixBadge: reply.isUploader ? CommentUPBadge.inlineImage(size: size, scale: scale, color: color, scheme: scheme) : nil,
            prefixSuffix: "：", jumpURLs: comment.content.jumpURLs)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "neobili", url.host == "comment-author" { openAuthor?(comment.member) }
                else { openURL(url) }
                return .handled
            })
            .frame(maxWidth: .infinity, alignment: .leading)
            .commentActions(comment: comment, root: root, surface: .secondarySystemBackground,
                            isDeleting: reply.isDeleting)
            .disabled(reply.isDeleting)
            .opacity(reply.isDeleting ? 0.5 : 1)
            .accessibilityIdentifier("comment.preview.\(comment.id)")
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
