import SwiftUI

/// 视频下方选项栏的排版参数都集中在这里。
/// 如果只想微调界面，修改下面的数字即可，不需要改程序逻辑。
private enum VideoSectionBarLayout {
    /// 分段控件与屏幕左右边缘的距离。
    static let horizontalPadding: CGFloat = 8
    /// 分段控件靠左、限宽，右侧留给「发弹幕」。
    static let pickerMaxWidth: CGFloat = 300
    /// 分段控件上方的留白。
    static let topPadding: CGFloat = 6
    /// 分段控件与下方内容的间距。
    static let bottomPadding: CGFloat = 6
}

/// 播放器下方、内容区上方的选项栏：左侧切换简介和评论，右侧是「发弹幕」（布局参考 PiliPlus）。
///
/// 用系统的分段控件（`Picker` + `.pickerStyle(.segmented)`）：选中态、按下态、
/// 深浅色、动态字体、无障碍全部跟着系统走，iOS 26 上还自带 Liquid Glass 的观感。
///
/// 不画卡片、不画分隔线，也不画背景：它挂在简介和评论两页的顶部栏里，
/// 内容从下面滑过时由系统的顶部模糊衬底。
struct VideoSectionBar: View {
    @Binding var selection: VideoPageSection
    /// 评论总数，跟在「评论」后面显示。还没加载出来（为 0）时不显示，
    /// 免得先出现一个 0 再跳成真实数字。
    var commentCount: Int = 0
    /// 打开发弹幕面板。为 nil（详情还没加载好）时不显示按钮。
    var onSendDanmaku: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Picker("视频内容", selection: animatedSelection) {
                ForEach(VideoPageSection.allCases) { section in
                    Text(title(for: section)).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: VideoSectionBarLayout.pickerMaxWidth)

            Spacer(minLength: 0)

            if let onSendDanmaku {
                Button("发弹幕", systemImage: "text.bubble", action: onSendDanmaku)
                    .font(.footnote.weight(.medium))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(.primary)
                    .accessibilityIdentifier("video.sendDanmaku")
            }
        }
        .padding(.horizontal, VideoSectionBarLayout.horizontalPadding)
        .padding(.top, VideoSectionBarLayout.topPadding)
        .padding(.bottom, VideoSectionBarLayout.bottomPadding)
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
