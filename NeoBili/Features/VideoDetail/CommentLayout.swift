import SwiftUI

enum CommentLayout {
    static let pageHorizontalInset: CGFloat = 16
    /// 每条评论上下的留白。评论之间没有分隔线，相邻两条靠两份留白分开。
    static let rowVerticalPadding: CGFloat = 12
    static let avatarSize: CGFloat = 32
    static let avatarTextSpacing: CGFloat = 10
    static let nameMessageSpacing: CGFloat = 4
    static let textVerticalSpacing: CGFloat = 5
    static let actionRowGap: CGFloat = 2
    static let replyBlockGap: CGFloat = 2
    static let replyCornerRadius: CGFloat = 12
    static let replyHorizontalPadding: CGFloat = 12
    static let replyVerticalPadding: CGFloat = 10
    static let replySpacing: CGFloat = 6
    /// 昵称、回复人名字与操作按钮的颜色强度（相对主文字色）。
    static let emphasisOpacity: Double = 0.8
    /// 时间与 IP 属地的颜色强度（相对主文字色），深浅色下都保持足够对比。
    static let metadataOpacity: Double = 0.6
    /// 长评论收起时显示几行。想让收起状态更高或更矮，改这个数字即可。
    static let collapsedMessageLines = 6
}
