#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI

/// @Entry 的默认值在每次读取时都会求值，类类型会因此被反复分配；
/// 兜底动作共用这一个全局实例（没有 host 接住时的空操作）。
/// 实例本身从不被改写（真正的动作都在 host 各自的盒子上），按非隔离常量处理。
nonisolated(unsafe) private let unhostedCommentThreadAction = EnvironmentAction<Comment> { _ in }

extension EnvironmentValues {
    /// 打开某条评论的单独页面。由最近的一个 `commentThreadHost(viewModel:)` 接住。
    /// 用引用盒子而不是裸闭包，见 `EnvironmentAction` 的说明。
    @Entry var openCommentThread = unhostedCommentThreadAction
}

extension View {
    /// 在这一屏挂一个楼中楼页面。评论列表里的任何一行都能通过
    /// `@Environment(\.openCommentThread)` 把它推出来。
    ///
    /// 回复单独呈现；它自己的导航栈用于打开评论者主页。
    func commentThreadHost(viewModel: CommentsViewModel, showsLoadingSkeleton: Bool = false) -> some View {
        modifier(CommentThreadHost(viewModel: viewModel, showsLoadingSkeleton: showsLoadingSkeleton))
    }
}

private struct CommentThreadHost: ViewModifier {
    let viewModel: CommentsViewModel
    let showsLoadingSkeleton: Bool
    @State private var root: Comment?
    @State private var openAction = EnvironmentAction<Comment> { _ in }

    func body(content: Content) -> some View {
        content
            .environment(\.openCommentThread, openAction)
            .onAppear {
                openAction.setHandler { [root = $root] in root.wrappedValue = $0 }
            }
            .sheet(item: $root) { comment in
                CommentThreadView(root: comment, viewModel: viewModel, showsLoadingSkeleton: showsLoadingSkeleton)
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
    private let showsLoadingSkeleton: Bool
    private let actions: CommentRowActions

    @Environment(\.dismiss) private var dismiss
    @Environment(ActionFeedback.self) private var feedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CardAnimationSettings.masterKey) private var cardAnimations = CardAnimationSettings.defaultValue

    init(root: Comment, viewModel: CommentsViewModel, showsLoadingSkeleton: Bool = false) {
        self.root = root
        self.viewModel = viewModel
        self.showsLoadingSkeleton = showsLoadingSkeleton
        self.actions = CommentRowActions(viewModel: viewModel)
    }

    private var replies: [Comment] { viewModel.allReplies(for: root) }

    var body: some View {
        let replies = replies
        let tailIDs = Set(replies.suffix(3).map(\.id))
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // 根评论自己不再画楼中楼那一块——它下面接的就是全部回复。
                    CommentRow(model: viewModel.rowModel(for: viewModel.currentRoot(root),
                                                         root: root, showsReplies: false),
                               actions: actions)
                        .equatable()
                        .padding(.horizontal, CommentLayout.pageHorizontalInset)
                        .padding(.vertical, CommentLayout.rowVerticalPadding)

                    Divider()

                    sectionHeader

                    ForEach(replies) { reply in
                        let loadsMore = tailIDs.contains(reply.id)
                        CommentRow(model: viewModel.rowModel(for: reply, root: root, showsReplies: false),
                                   actions: actions)
                            .equatable()
                            .removalFillTransition()
                            .padding(.horizontal, CommentLayout.pageHorizontalInset)
                            .padding(.vertical, CommentLayout.rowVerticalPadding)
                            .task(id: loadsMore) {
                                guard loadsMore else { return }
                                await viewModel.loadMoreRepliesIfNeeded(current: reply, root: root)
                            }
                    }

                    footer
                }
                .removalFill(ids: replies.map(\.id), enabled: cardAnimations && !reduceMotion)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollEdgeEffectHidden(true, for: .bottom)
            .background(Color(uiColor: .systemBackground))
            .commentComposer(viewModel: viewModel, root: root)
            .commentAuthorHost()
            // 顶部下拉留给 sheet 退出。列表停在顶部时，系统接手向下拖动；
            // 离开顶部时仍由列表滚动。刷新控件会抢走这段手势。
            .navigationTitle("回复")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭", systemImage: "xmark") { dismiss() }
                }
            }
            // 这一页在 sheet 里，父级的图片查看器盖不进来，自己挂一个。
            .imageViewerHost()
            .commentLinkHost(beforeOpeningVideo: { dismiss() })
        }
        .presentationDragIndicator(.visible)
        .task { await viewModel.loadRepliesIfNeeded(for: root) }
        .onChange(of: viewModel.deletedIDs.contains(root.id)) { _, deleted in
            if deleted { dismiss() }
        }
        // 和评论列表一样走非模态浮层，别用 alert 去和外层的 present 抢。
        .onChange(of: viewModel.actionMessage) { _, message in
            guard let message else { return }
            feedback.show(message)
            viewModel.actionMessage = nil
        }
        .actionFeedbackOverlay()
    }

    private var sectionHeader: some View {
        let count = viewModel.replyCount(for: root)
        return Text(count > 0 ? String(localized: "全部回复 \(count)") : String(localized: "全部回复"))
            .font(.app(.footnote, weight: .semibold))
            .foregroundStyle(.primary.opacity(CommentLayout.emphasisOpacity))
            .padding(.horizontal, CommentLayout.pageHorizontalInset)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    @ViewBuilder
    private var footer: some View {
        if showsLoadingSkeleton, viewModel.isWaitingForFirstReplies(root) {
            VideoCommentSkeleton(rowCount: 2, label: "正在加载回复")
        } else if viewModel.isLoadingReplies(root) {
            LoadingTaskAnchor()
                .frame(maxWidth: .infinity)
                .padding()
        } else if let error = viewModel.replyErrors[root.id] {
            VStack(spacing: 10) {
                Text(error)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("重试") {
                    Task { await viewModel.retryReplies(for: root) }
                }
                .font(.app(.subheadline, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding()
        } else if replies.isEmpty {
            ContentUnavailableView("还没有回复", systemImage: "bubble.left")
                .padding(.vertical, 40)
        }
    }

}
