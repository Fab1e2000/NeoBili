import SwiftUI

/// 评论页的排版参数都集中在这里。
/// 如果只想微调界面，修改下面的数字即可，不需要改程序逻辑。
enum CommentLayout {
    /// 评论内容与屏幕左右边缘的距离。
    static let pageHorizontalInset: CGFloat = 16
    /// 每条评论上下的留白，也就是内容到分隔线的距离。
    static let rowVerticalPadding: CGFloat = 12
    /// 头像直径。
    static let avatarSize: CGFloat = 32
    /// 头像和右侧文字之间的距离。
    static let avatarTextSpacing: CGFloat = 10
    /// 用户名、正文、点赞行之间的竖向距离。
    static let textVerticalSpacing: CGFloat = 5
    /// 正文与轻量操作行之间的距离。
    static let actionRowGap: CGFloat = 2
    /// 楼中楼区块与上方点赞行之间的距离。
    static let replyBlockGap: CGFloat = 4
    /// 楼中楼区块的圆角。
    static let replyCornerRadius: CGFloat = 16
    /// 楼中楼区块内部的留白。
    static let replyPadding: CGFloat = 10
    /// 楼中楼每条回复之间的距离。
    static let replySpacing: CGFloat = 7
    /// 长评论收起时显示几行。想让收起状态更高或更矮，改这个数字即可。
    static let collapsedMessageLines = 6
}
