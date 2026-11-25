import NeoBiliDomain
import SwiftUI

/// 评论列表本体（没有自己的 ScrollView）。
///
/// 视频页把它放进 `CommentsView` 的滚动容器里；动态详情页要在同一个滚动区
/// 里先放动态内容再接评论，所以需要这层不带容器的版本——两个 ScrollView
/// 套在一起没法正常滚动。
struct CommentsList: View {
    let viewModel: CommentsViewModel
    private let actions: CommentRowActions
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CardAnimationSettings.masterKey) private var cardAnimations = CardAnimationSettings.defaultValue

    init(viewModel: CommentsViewModel) {
        self.viewModel = viewModel
        self.actions = CommentRowActions(viewModel: viewModel)
    }

    var body: some View {
        let rows = viewModel.rootRowModels
        let paginationIDs = Set(rows.suffix(CommentsViewModel.paginationWindow).map(\.comment.id))
        LazyVStack(alignment: .leading, spacing: 0) {
            CommentSortHeader(viewModel: viewModel)
            if let message = viewModel.errorMessage, !rows.isEmpty, viewModel.didFailReload {
                loadError(message)
            }
            ForEach(rows, id: \.comment.id) { row in
                let comment = row.comment
                // 评论之间不画分隔线，只靠上下留白分开。
                // 分页触发由父级一次算好；行任务只在进入/离开末尾窗口时重启，
                // 追加一页不会让所有行重新挂任务。
                CommentRow(model: row, actions: actions)
                    .equatable()
                    .removalFillTransition()
                    .padding(.horizontal, CommentLayout.pageHorizontalInset)
                    .padding(.vertical, CommentLayout.rowVerticalPadding)
                    .task(id: paginationIDs.contains(comment.id)) {
                        guard paginationIDs.contains(comment.id) else { return }
                        await viewModel.loadMoreIfNeeded(current: comment)
                    }
            }

            if viewModel.isLoadingMore {
                LoadingTaskAnchor()
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            if let message = viewModel.errorMessage, !rows.isEmpty, !viewModel.didFailReload {
                loadError(message)
            }
        }
        .removalFill(ids: rows.map(\.comment.id), enabled: cardAnimations && !reduceMotion)
        .commentThreadHost(viewModel: viewModel)
        .commentLinkHost()
        // 和视频页一样走非模态浮层，别用 alert 去和 fullScreenCover 抢 present。
        .onChange(of: viewModel.actionMessage) { _, message in
            guard let message else { return }
            feedback.show(message)
            viewModel.actionMessage = nil
        }
    }

    private func loadError(_ message: String) -> some View {
        CommentListLoadFailure(viewModel: viewModel, message: message)
    }
}

/// 视频页的评论列表。视图模型由视频页持有，所以在简介和评论之间切换时
/// 已经加载的内容和展开状态都不会丢失。列表容器是复用宿主的集合视图，
/// 行只在值快照变化时重新配置。
struct CommentsView: View {
    let viewModel: CommentsViewModel
    /// 保留给页面级滚动状态的调用方；集合视图自己持有实际滚动位置。
    @Binding var scrollPosition: ScrollPosition
    var initialOffset: CGFloat = 0
    var onOffsetChanged: ((CGFloat) -> Void)? = nil
    @Environment(\.videoScrollContext) private var geometry
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CardAnimationSettings.masterKey) private var cardAnimations = CardAnimationSettings.defaultValue
    var collapseConsume: ((CGFloat) -> CGFloat)? = nil
    var collapseEnd: (() -> Void)? = nil
    var canCollapse: ((CGFloat) -> Bool)? = nil
    var collapseCanContinue: (() -> Bool)? = nil

    var body: some View {
        CommentCollectionView(
            viewModel: viewModel,
            rows: viewModel.rootRowModels,
            rowsRevision: viewModel.rowsRevision,
            scrollRevision: viewModel.scrollRevision,
            initialOffset: initialOffset,
            onOffsetChanged: onOffsetChanged,
            collapseConsume: collapseConsume,
            collapseEnd: collapseEnd,
            canCollapse: canCollapse,
            animatesRemoval: cardAnimations && !reduceMotion
        )
        .overlay {
            if viewModel.comments.isEmpty, !viewModel.isWaitingForFirstComments {
                GeometryReader { proxy in
                    let hiddenTop = max(0, (geometry?.reservation ?? 0) - (geometry?.distance() ?? 0))
                    CommentsPlaceholder(viewModel: viewModel)
                        .frame(width: proxy.size.width, height: max(0, proxy.size.height - hiddenTop))
                        .offset(y: hiddenTop)
                }
            }
        }
        .task { await viewModel.loadInitial() }
        .commentThreadHost(viewModel: viewModel, showsLoadingSkeleton: true)
        .commentLinkHost()
        // 和视频页一样走非模态浮层，别用 alert 去和 fullScreenCover 抢 present。
        .onChange(of: viewModel.actionMessage) { _, message in
            guard let message else { return }
            feedback.show(message)
            viewModel.actionMessage = nil
        }
        .commentComposer(viewModel: viewModel)
    }
}

/// 集合视图末尾的加载与错误行；只观察模型，不参与行快照比较。
struct CommentListFooter: View {
    let viewModel: CommentsViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isWaitingForFirstComments {
                VideoCommentSkeleton(rowCount: 3, label: "正在加载评论")
            } else if viewModel.isLoadingMore {
                LoadingTaskAnchor()
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            if let message = viewModel.errorMessage, !viewModel.comments.isEmpty, !viewModel.didFailReload {
                CommentListLoadFailure(viewModel: viewModel, message: message)
            }
        }
    }
}

struct CommentListLoadFailure: View {
    let viewModel: CommentsViewModel
    let message: String

    var body: some View {
        InlineLoadFailure(title: viewModel.didFailReload ? "评论未能更新" : "无法加载更多评论",
                          message: message, retryTitle: "重试加载评论",
                          isRetryDisabled: viewModel.isLoading || viewModel.isRefreshing || viewModel.isLoadingMore) {
            Task { await viewModel.retry() }
        }
    }
}

/// 评论模型尚未建立时，也使用同一份顶部预留与可见窗口。
struct VideoCommentsLoadingView: View {
    let consume: (CGFloat) -> CGFloat
    let canConsume: (CGFloat) -> Bool
    var showsSkeleton = true
    @Environment(\.videoScrollContext) private var geometry

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if showsSkeleton {
                    VideoCommentSkeleton(rowCount: 3, label: "正在加载评论")
                        .padding(.top, CommentSortHeader.minimumHeight)
                }
            }
            .frame(maxWidth: .infinity, minHeight: geometry?.minimumContentHeight ?? 0, alignment: .top)
            .background {
                PausedVideoCollapseScroll(consume: consume, end: {}, canConsume: canConsume)
                    .allowsHitTesting(false)
            }
            // Keep the reservation inside the content: a scroll margin also
            // clips the list independently of the moving native viewport.
            .padding(.top, geometry?.reservation ?? 0)
        }
        .scrollBounceBehavior(.always, axes: .vertical)
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
