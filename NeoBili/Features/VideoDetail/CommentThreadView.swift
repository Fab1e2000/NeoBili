import SwiftUI

extension EnvironmentValues {
    /// 打开某条评论的单独页面。由最近的一个 `commentThreadHost(viewModel:)` 接住。
    @Entry var openCommentThread: (Comment) -> Void = { _ in }
}

extension View {
    /// 在这一屏挂一个楼中楼页面。评论列表里的任何一行都能通过
    /// `@Environment(\.openCommentThread)` 把它推出来。
    ///
    /// 用 sheet 而不是 NavigationLink：视频页是从根视图 present 出来的
    /// fullScreenCover，里面没有导航栈，push 不了。
    func commentThreadHost(viewModel: CommentsViewModel) -> some View {
        modifier(CommentThreadHost(viewModel: viewModel))
    }
}

private struct CommentThreadHost: ViewModifier {
    let viewModel: CommentsViewModel
    @State private var root: Comment?

    func body(content: Content) -> some View {
        content
            .environment(\.openCommentThread) { root = $0 }
            .sheet(item: $root) { comment in
                CommentThreadView(root: comment, viewModel: viewModel)
                    .environment(\.commentBottomInset, 0)
            }
    }
}

/// 一条评论的单独页面：上面是这条评论本身，下面是它的全部回复。
///
/// 回复用的是和一级评论同一个 `CommentRow`，所以头像、表情、配图、时间、
/// 点赞按钮全都现成——点赞走同一个 `toggleLike`，接口本来就按 rpid 认，
/// 楼中楼和一级评论没有区别。
struct CommentThreadView: View {
    let root: Comment
    let viewModel: CommentsViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(ActionFeedback.self) private var feedback

    private var replies: [Comment] { viewModel.allReplies(for: root) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // 根评论自己不再画楼中楼那一块——它下面接的就是全部回复。
                    CommentRow(comment: root, viewModel: viewModel, showsReplies: false)
                        .padding(.horizontal, CommentLayout.pageHorizontalInset)
                        .padding(.vertical, CommentLayout.rowVerticalPadding)

                    Divider()

                    sectionHeader

                    ForEach(replies) { reply in
                        CommentRow(comment: reply, viewModel: viewModel, showsReplies: false)
                            .padding(.horizontal, CommentLayout.pageHorizontalInset)
                            .padding(.vertical, CommentLayout.rowVerticalPadding)
                            .task { await loadMoreIfNeeded(current: reply) }

                        if reply.id != replies.last?.id {
                            Divider()
                                .padding(.leading, CommentLayout.pageHorizontalInset)
                        }
                    }

                    footer
                }
            }
            .commentComposer(viewModel: viewModel, root: root)
            .navigationTitle("回复")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            // 这一页在 sheet 里，父级的图片查看器盖不进来，自己挂一个。
            .imageViewerHost()
        }
        .task { await viewModel.loadRepliesIfNeeded(for: root) }
        // 和评论列表一样走非模态浮层，别用 alert 去和外层的 present 抢。
        .onChange(of: viewModel.actionMessage) { _, message in
            guard let message else { return }
            feedback.show(message)
            viewModel.actionMessage = nil
        }
        .actionFeedbackOverlay()
    }

    private var sectionHeader: some View {
        Text(root.rcount > 0 ? "全部回复 \(root.rcount)" : "全部回复")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, CommentLayout.pageHorizontalInset)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    @ViewBuilder
    private var footer: some View {
        if viewModel.isLoadingReplies(root) {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding()
        } else if let error = viewModel.replyErrors[root.id] {
            VStack(spacing: 10) {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("重试") {
                    Task { await viewModel.loadMoreReplies(for: root) }
                }
                .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding()
        } else if replies.isEmpty {
            ContentUnavailableView("还没有回复", systemImage: "bubble.left")
                .padding(.vertical, 40)
        }
    }

    /// 滚到末尾再翻一页。和一级评论那边同一个规矩。
    private func loadMoreIfNeeded(current reply: Comment) async {
        guard viewModel.hasMoreReplies(root), !viewModel.isLoadingReplies(root) else { return }
        guard replies.suffix(3).contains(where: { $0.id == reply.id }) else { return }
        await viewModel.loadMoreReplies(for: root)
    }
}
