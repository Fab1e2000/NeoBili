import NeoBiliDomain
import SwiftUI

/// 由评论模型即时快照的入口，供测试与不便持有模型的地方使用；
/// 列表本身直接构建 `CommentRowModel`，让相等比较生效。
struct SnapshotCommentRow: View {
    let comment: Comment
    let viewModel: CommentsViewModel
    var showsReplies = true
    var root: Comment? = nil

    var body: some View {
        CommentRow(model: viewModel.rowModel(for: comment, root: root, showsReplies: showsReplies),
                   actions: CommentRowActions(viewModel: viewModel))
    }
}
