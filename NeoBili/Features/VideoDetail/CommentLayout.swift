import SwiftUI

/// 评论页的排版参数都集中在这里。
/// 如果只想微调界面，修改下面的数字即可，不需要改程序逻辑。
enum CommentLayout {
    /// 评论内容与屏幕左右边缘的距离。
    static let pageHorizontalInset: CGFloat = 16
    /// 每条评论上下的留白。评论之间没有分隔线，相邻两条靠两份留白分开。
    static let rowVerticalPadding: CGFloat = 12
    /// 头像直径。
    static let avatarSize: CGFloat = 32
    /// 头像和右侧文字之间的距离。
    static let avatarTextSpacing: CGFloat = 10
    /// 用户名与正文之间的竖向距离。
    static let nameMessageSpacing: CGFloat = 4
    /// 正文与配图、正文与「展开」之间的竖向距离。
    static let textVerticalSpacing: CGFloat = 5
    /// 正文与轻量操作行之间的距离。
    static let actionRowGap: CGFloat = 2
    /// 楼中楼区块与上方点赞行之间的距离。
    static let replyBlockGap: CGFloat = 2
    /// 楼中楼区块的圆角。
    static let replyCornerRadius: CGFloat = 12
    /// 楼中楼区块内部左右的留白。
    static let replyHorizontalPadding: CGFloat = 12
    /// 楼中楼区块内部上下的留白。
    static let replyVerticalPadding: CGFloat = 10
    /// 楼中楼每条回复之间的距离。
    static let replySpacing: CGFloat = 6
    /// 昵称、回复人名字与操作按钮的颜色强度（相对主文字色）。
    static let emphasisOpacity: Double = 0.8
    /// 时间与 IP 属地的颜色强度（相对主文字色），深浅色下都保持足够对比。
    static let metadataOpacity: Double = 0.6
    /// 长评论收起时显示几行。想让收起状态更高或更矮，改这个数字即可。
    static let collapsedMessageLines = 6
}
