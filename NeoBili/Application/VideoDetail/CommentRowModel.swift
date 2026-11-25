import NeoBiliDomain
import Foundation

/// 评论行显示所需的全部值。父级在一次求值里快照出它，行本身不再观察模型；
/// 输入不变的行由 `Equatable` 跳过 body 重建。
struct CommentRowModel: Equatable, Sendable {
    struct Reply: Equatable, Sendable {
        let comment: Comment
        let isUploader: Bool
        let isDeleting: Bool
    }

    let comment: Comment
    let root: Comment?
    let showsReplies: Bool
    let isUploader: Bool
    let isPinned: Bool
    let isDeleting: Bool
    let isExpanded: Bool
    let isLiked: Bool
    let likeCount: Int
    let replyCount: Int
    let previewReplies: [Reply]
    let showsAllReplies: Bool
}

/// 行内动作。引用盒子不参与相等比较，输入不变的行仍可跳过 body。
@MainActor
final class CommentRowActions {
    private let viewModel: CommentsViewModel

    init(viewModel: CommentsViewModel) { self.viewModel = viewModel }

    func toggleLike(_ comment: Comment, isLoggedIn: Bool) {
        Task { await viewModel.toggleLike(comment, isLoggedIn: isLoggedIn) }
    }

    func toggleExpansion(_ comment: Comment) {
        viewModel.toggleExpanded(comment)
    }

    func copyMessage(_ message: String) {
        viewModel.actionMessage = String(localized: "已复制全文")
    }

    func canDelete(_ comment: Comment, accountID: Int?, isLoggedIn: Bool) -> Bool {
        viewModel.canDelete(comment, accountID: accountID, isLoggedIn: isLoggedIn)
    }

    func deletion(for comment: Comment, root: Comment?, accountID: Int?, isLoggedIn: Bool) -> CommentsViewModel.Deletion? {
        viewModel.deletion(for: comment, root: root, accountID: accountID, isLoggedIn: isLoggedIn)
    }

    func delete(_ deletion: CommentsViewModel.Deletion, accountID: Int?, isLoggedIn: Bool) {
        Task { await viewModel.delete(deletion, accountID: accountID, isLoggedIn: isLoggedIn) }
    }
}
