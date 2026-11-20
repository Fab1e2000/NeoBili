import SwiftUI

private enum VideoSectionBarLayout {
    static let horizontalPadding: CGFloat = 8
    /// 宽屏上分段控件不再继续拉长，避免两个标题被撑得过开。
    static let pickerMaxWidth: CGFloat = 300
    static let topPadding: CGFloat = 6
    static let bottomPadding: CGFloat = 6
    static let controlGap: CGFloat = 8
}

/// 播放器下方、内容区上方的选项栏：简介和评论用分段控件，「发弹幕」紧贴在它右侧。
///
/// 用系统的分段控件（`Picker` + `.pickerStyle(.segmented)`）：选中态、按下态、
/// 深浅色、动态字体、无障碍全部跟着系统走，iOS 26 上还自带 Liquid Glass 的观感。
/// 发弹幕按钮跟分段控件同一高度，中间不留弹性空隙，避免胶囊悬在右缘、上下也对不齐。
///
/// 不画卡片、不画分隔线，也不画背景：它挂在简介和评论两页的顶部栏里，
/// 内容从下面滑过时由系统的顶部模糊衬底。
struct VideoSectionBar: View {
    @Binding var selection: VideoPageSection
    /// 评论总数，跟在「评论」后面显示。还没加载出来（为 0）时不显示，
    /// 免得先出现一个 0 再跳成真实数字。
    var commentCount: Int = 0
    var showsComments = true
    /// 打开发弹幕面板。为 nil（详情还没加载好）时不显示按钮。
    var onSendDanmaku: (() -> Void)?
    @State private var segmentHeight: CGFloat = 0

    var body: some View {
        HStack(spacing: VideoSectionBarLayout.controlGap) {
            Picker("视频内容", selection: animatedSelection) {
                ForEach(showsComments ? VideoPageSection.allCases : [.description]) { section in
                    Text(title(for: section)).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // 先吃掉按钮以外的宽度，再限制上限。只写 maxWidth 时分段控件会停在内容宽度，
            // 把空档留在和发弹幕之间。
            .frame(maxWidth: .infinity)
            .frame(maxWidth: VideoSectionBarLayout.pickerMaxWidth)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { segmentHeight = $0 }

            if let onSendDanmaku {
                Button(action: onSendDanmaku) {
                    Label("发弹幕", systemImage: "text.bubble")
                }
                .buttonStyle(SectionBarDanmakuButtonStyle(height: segmentHeight))
                .fixedSize(horizontal: true, vertical: true)
                .layoutPriority(1)
                .accessibilityIdentifier("video.sendDanmaku")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

/// 发弹幕胶囊的外径跟分段控件一致。系统 bordered 按钮的可视胶囊更矮，
/// 还会在布局框外留一圈空白，和旁边的分段条对不齐。
private struct SectionBarDanmakuButtonStyle: ButtonStyle {
    var height: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.app(.footnote, weight: .medium))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 12)
            .frame(height: height > 1 ? height : nil)
            .foregroundStyle(.primary)
            .glassEffect(.regular.interactive(), in: Capsule())
    }
}
