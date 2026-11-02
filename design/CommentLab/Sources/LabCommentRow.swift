import SwiftUI

struct LabCommentRow: View {
    let comment: LabComment
    var rootID: Int?
    var showsReplies = true
    @Environment(LabModel.self) private var model
    @State private var expanded = false

    private var target: CommentActionTarget { .init(comment: comment, rootID: rootID) }
    private var emphasized: Bool { model.variant == .c && comment.pinned }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { model.path.append(.author(comment.author)) } label: {
                LabAvatar(author: comment.author, size: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看\(comment.author.name)的主页")
            .accessibilityIdentifier("avatar.\(comment.id)")

            VStack(alignment: .leading, spacing: 0) {
                authorLine
                if model.variant == .b && (comment.pinned || comment.upLiked || comment.upReplied) {
                    statusLine.padding(.top, 5)
                }
                message.padding(.top, 4)
                    .contentShape(Rectangle())
                    .modifier(LabCommentActions(target: target))
                if comment.hasPicture {
                    Button { model.showImage = true } label: {
                        LabLandscape()
                            .frame(maxWidth: 245).aspectRatio(1.45, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("查看评论图片")
                    .accessibilityIdentifier("comment.image.\(comment.id)")
                    .padding(.top, 7)
                }
                if model.variant != .b && (comment.upLiked || comment.upReplied) {
                    statusLine.padding(.top, model.variant == .c ? 10 : 6)
                }
                metadata.padding(.top, 2)
                if showsReplies && !comment.replies.isEmpty { replies.padding(.top, 2) }
            }
        }
        .padding(emphasized ? 10 : 0)
        .background {
            if emphasized {
                RoundedRectangle(cornerRadius: 14).fill(LabModel.tint.opacity(0.065))
            }
        }
        .opacity(model.deletingID == comment.id ? 0.45 : 1)
        .overlay(alignment: .topTrailing) {
            if model.deletingID == comment.id { ProgressView().controlSize(.small).padding(12) }
        }
        .disabled(model.deletingID == comment.id)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("comment.row.\(comment.id)")
    }

    private var authorLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Button { model.path.append(.author(comment.author)) } label: {
                Text(comment.author.name)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary.opacity(0.8))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("author.\(comment.id)")
            if comment.isUploader { LabUPBadge(variant: model.variant).layoutPriority(1) }
            if comment.isMine {
                Text("我").font(.caption2).foregroundStyle(.secondary).fixedSize()
            }
            Spacer(minLength: 0)
        }
    }

    private var message: some View {
        VStack(alignment: .leading, spacing: 5) {
            if comment.pinned && model.variant != .b {
                Label("置顶", systemImage: "pin.fill")
                    .font(.caption2.weight(.medium)).foregroundStyle(LabModel.tint)
            }
            Text(attributedMessage)
                .font(.body).foregroundStyle(.primary)
                .lineLimit(expanded ? nil : 6)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.openURL, OpenURLAction { url in
                    if url.scheme == "commentlab", url.host == "time" {
                        model.playbackTime = "03:18"
                        model.announce(model.scene == .video ? "已跳到 03:18" : "动态评论不跳转视频")
                    }
                    return .handled
                })
                .accessibilityIdentifier("comment.message.\(comment.id)")
            if comment.message.count > 120 {
                Button(expanded ? "收起" : "展开") { expanded.toggle() }
                    .font(.caption.weight(.medium)).frame(minHeight: 32)
                    .accessibilityIdentifier("comment.expand.\(comment.id)")
            }
        }
    }

    private var attributedMessage: AttributedString {
        var value = AttributedString(comment.displayedMessage)
        if model.scene == .video, let range = value.range(of: "03:18") {
            value[range].link = URL(string: "commentlab://time/198")
            value[range].foregroundColor = .blue
        }
        return value
    }

    private var statusLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { statusLabels }
            VStack(alignment: .leading, spacing: 4) { statusLabels }
        }
        .font(.caption2)
        .foregroundStyle(model.variant == .c ? LabModel.tint : .secondary)
    }

    @ViewBuilder private var statusLabels: some View {
        if model.variant == .b && comment.pinned {
            Label("置顶", systemImage: "pin.fill").foregroundStyle(LabModel.tint)
        }
        if comment.upLiked { Label("UP 主觉得很赞", systemImage: "hand.thumbsup") }
        if comment.upReplied { Label("UP 主回复过", systemImage: "bubble.left") }
    }

    private var metadata: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { timeLabel; actionButtons }
            VStack(alignment: .leading, spacing: 0) { timeLabel; actionButtons }
        }
    }

    private var timeLabel: some View {
        Text("\(comment.time) · \(comment.location)")
            .font(.caption).foregroundStyle(.primary.opacity(0.6)).lineLimit(1)
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            Button { model.toggleLike(comment) } label: {
                Label("\(comment.likes + (model.likedIDs.contains(comment.id) ? 1 : 0))",
                      systemImage: model.likedIDs.contains(comment.id) ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .foregroundStyle(model.likedIDs.contains(comment.id) ? LabModel.tint : .secondary)
            }
            .accessibilityLabel(model.likedIDs.contains(comment.id) ? "取消点赞" : "点赞")
            .accessibilityIdentifier("comment.like.\(comment.id)")
            Button {
                model.replyTarget = target
            } label: {
                Label("回复", systemImage: "arrowshape.turn.up.left").foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("comment.reply.\(comment.id)")
        }
        .font(.caption)
        .buttonStyle(LabSmallActionStyle())
        .fixedSize(horizontal: true, vertical: false)
    }

    private var replies: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(comment.replies.prefix(2)) { reply in
                LabReplyPreview(reply: reply, rootID: comment.id)
            }
            Button { model.path.append(.thread(comment.id)) } label: {
                HStack(spacing: 3) {
                    Text("查看全部 \(comment.replies.count) 条回复")
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                }
                .font(.footnote.weight(.semibold))
                .frame(minHeight: 32, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("comment.thread.\(comment.id)")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct LabReplyPreview: View {
    let reply: LabComment
    let rootID: Int
    @Environment(LabModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        // Keep the compact preview in one flowing text paragraph; the author link has
        // its own destination, while the separate footer opens the whole thread.
        previewText
            .font(.footnote)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction { _ in
                model.path.append(.author(reply.author))
                return .handled
            })
            .padding(.vertical, 1)
            .contentShape(Rectangle())
            .modifier(LabCommentActions(target: .init(comment: reply, rootID: rootID)))
            .accessibilityIdentifier("reply.preview.\(reply.id)")
    }

    private var previewText: Text {
        var name = AttributedString(reply.author.name)
        name.font = .footnote.weight(.semibold)
        name.foregroundColor = .primary.opacity(0.8)
        name.link = URL(string: "commentlab://author/\(reply.author.id)")
        if reply.isUploader {
            // Render the same native badge inline so the paragraph can still wrap
            // naturally and only its author name remains a profile link.
            let renderer = ImageRenderer(content: LabUPBadge(variant: model.variant)
                .environment(\.dynamicTypeSize, dynamicTypeSize))
            renderer.scale = displayScale
            if let badge = renderer.uiImage {
                return Text("\(Text(name)) \(Text(Image(uiImage: badge)).baselineOffset(-3))：\(reply.displayedMessage)")
            }
        }
        return Text("\(Text(name))：\(reply.displayedMessage)")
    }
}

struct LabUPBadge: View {
    let variant: LabVariant
    var body: some View {
        Text("UP 主")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .foregroundStyle(variant == .c ? .white : LabModel.tint)
            .background {
                if variant != .a {
                    RoundedRectangle(cornerRadius: 4).fill(LabModel.tint.opacity(variant == .c ? 1 : 0.10))
                }
            }
            .overlay {
                if variant == .a { RoundedRectangle(cornerRadius: 4).strokeBorder(LabModel.tint.opacity(0.65), lineWidth: 0.7) }
            }
            .fixedSize()
            .accessibilityLabel("UP 主")
    }
}

private struct LabSmallActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 6).frame(minWidth: 44, minHeight: 32)
            .contentShape(Rectangle()).opacity(configuration.isPressed ? 0.5 : 1)
    }
}

private struct LabCommentActions: ViewModifier {
    let target: CommentActionTarget
    @Environment(LabModel.self) private var model

    @ViewBuilder func body(content: Content) -> some View {
        if model.variant == .b {
            content.highPriorityGesture(
                LongPressGesture(minimumDuration: 0.45)
                    .onEnded { _ in model.actionSheet = target }
            )
        } else {
            content.contextMenu {
                Button("复制全文", systemImage: "doc.on.doc") { model.copy(target.comment) }
                    .accessibilityIdentifier("comment.copy")
                if target.comment.isMine {
                    Button("删除评论", systemImage: "trash", role: .destructive) { model.pendingDeletion = target }
                        .accessibilityIdentifier("comment.delete")
                }
            }
        }
    }
}
