import SwiftUI

/// 评论列表本体（没有自己的 ScrollView）。
///
/// 视频页把它放进 `CommentsView` 的滚动容器里；动态详情页要在同一个滚动区
/// 里先放动态内容再接评论，所以需要这层不带容器的版本——两个 ScrollView
/// 套在一起没法正常滚动。
struct CommentsList: View {
    let viewModel: CommentsViewModel
    @Environment(ActionFeedback.self) private var feedback

    var body: some View {
        let comments = viewModel.comments
        let lastCommentID = comments.last?.id
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(comments) { comment in
                VStack(alignment: .leading, spacing: 0) {
                    CommentRow(comment: comment, viewModel: viewModel)
                        .padding(.horizontal, CommentLayout.pageHorizontalInset)
                        .padding(.vertical, CommentLayout.rowVerticalPadding)
                    if comment.id != lastCommentID {
                        Divider().padding(.leading, CommentLayout.pageHorizontalInset)
                    }
                }
                .task(id: comments.suffix(5).contains(where: { $0.id == comment.id }) ? lastCommentID : nil) {
                    guard comments.suffix(5).contains(where: { $0.id == comment.id }) else { return }
                    await viewModel.loadMoreIfNeeded(current: comment)
                }
            }

            if viewModel.isLoadingMore {
                LoadingTaskAnchor()
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            if let message = viewModel.errorMessage, !viewModel.comments.isEmpty {
                VStack(spacing: 8) {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                    Button("重试加载评论") { Task { await viewModel.retry() } }
                        .disabled(viewModel.isLoading || viewModel.isLoadingMore)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
        .commentThreadHost(viewModel: viewModel)
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
    var collapseConsume: ((CGFloat) -> CGFloat)? = nil
    var collapseEnd: (() -> Void)? = nil
    var canCollapse: ((CGFloat) -> Bool)? = nil
    var collapseCanContinue: (() -> Bool)? = nil

    var body: some View {
        ScrollView {
            CommentsList(viewModel: viewModel)
                .background {
                    if let collapseConsume {
                        PausedVideoCollapseScroll(consume: collapseConsume, end: { collapseEnd?() },
                                                  canConsume: { canCollapse?($0) ?? false },
                                                  canContinue: { collapseCanContinue?() ?? false })
                            .allowsHitTesting(false)
                    }
                }
        }
        .scrollBounceBehavior(.always, axes: .vertical)
        .scrollPosition($scrollPosition)
        .overlay {
            CommentsPlaceholder(viewModel: viewModel)
        }
        .task { await viewModel.loadInitial() }
        .commentComposer(viewModel: viewModel)
    }
}

/// 加载中 / 失败 / 空评论三种占位，两个页面共用。
struct CommentsPlaceholder: View {
    let viewModel: CommentsViewModel

    var body: some View {
        if viewModel.isLoading {
            LoadingTaskAnchor()
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
