import Foundation

/// 视频页下半部分显示哪一块内容。
enum VideoPageSection: Hashable, CaseIterable, Identifiable {
    case description
    case comments

    var id: Self { self }

    var title: String {
        switch self {
        case .description: "简介"
        case .comments: "评论"
        }
    }

    var systemImage: String {
        switch self {
        case .description: "text.alignleft"
        case .comments: "bubble.left.and.bubble.right"
        }
    }
}
