import SwiftUI

/// 视频下方选项栏的排版参数都集中在这里。
/// 如果只想微调界面，修改下面的数字即可，不需要改程序逻辑。
private enum VideoSectionBarLayout {
    /// 分段控件与屏幕左右边缘的距离。
    static let horizontalPadding: CGFloat = 16
    /// 分段控件上方的留白。
    static let topPadding: CGFloat = 8
    /// 分段控件下方的留白。安全区之外还要留一点，控件不至于贴着屏幕底边。
    static let bottomPadding: CGFloat = 6
}

/// 视频页最下方的选项栏，切换简介和评论。
///
/// 用系统的分段控件（`Picker` + `.pickerStyle(.segmented)`）：选中态、按下态、
/// 深浅色、动态字体、无障碍全部跟着系统走，iOS 26 上还自带 Liquid Glass 的观感。
///
/// 它落在视频页的最底边，上方整块都留给简介/评论。视频页是从根视图 present
/// 出来的 fullScreenCover，屏幕底部没有系统标签栏，不会撞车。
///
/// 不画卡片、不画分隔线：控件直接坐在页面底色上，周围没有任何直角边框
/// 去和它的圆角对比。
struct VideoSectionBar: View {
    @Binding var selection: VideoPageSection
    /// 评论总数，跟在「评论」后面显示。还没加载出来（为 0）时不显示，
    /// 免得先出现一个 0 再跳成真实数字。
    var commentCount: Int = 0

    var body: some View {
        Picker("视频内容", selection: animatedSelection) {
            ForEach(VideoPageSection.allCases) { section in
                Text(title(for: section)).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, VideoSectionBarLayout.horizontalPadding)
        .padding(.top, VideoSectionBarLayout.topPadding)
        .padding(.bottom, VideoSectionBarLayout.bottomPadding)
        // 和上方内容同一个底色，连成一片。要漫过 Home 指示条那条安全区，
        // 否则栏下面会露出最外层那层黑。
        .background {
            Color(uiColor: .systemBackground).ignoresSafeArea(edges: .bottom)
        }
    }

    /// 分段控件改选中项时要带上动画，下面那对分页才是滑过去而不是瞬间跳过去。
    /// 反过来手指滑动分页时是外部改这个绑定，不经过这里的 setter，不会打架。
    private var animatedSelection: Binding<VideoPageSection> {
        Binding(
            get: { selection },
            set: { newValue in
                guard newValue != selection else { return }
                withAnimation(.easeInOut(duration: 0.25)) { selection = newValue }
            }
        )
    }

    private func title(for section: VideoPageSection) -> String {
        guard section == .comments, commentCount > 0 else { return section.title }
        return "\(section.title) \(commentCount.biliCountText)"
    }
}
