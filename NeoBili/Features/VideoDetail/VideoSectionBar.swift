import SwiftUI

/// 视频下方选项栏的排版参数都集中在这里。
/// 如果只想微调界面，修改下面的数字即可，不需要改程序逻辑。
private enum VideoSectionBarLayout {
    /// 文字上方的留白。
    static let topPadding: CGFloat = 10
    /// 文字和下方指示条之间的距离。
    static let textIndicatorSpacing: CGFloat = 7
    /// 指示条的粗细。
    static let indicatorHeight: CGFloat = 3
    /// 指示条的宽度。它比文字窄，看起来才像重点标记而不是下划线。
    static let indicatorWidth: CGFloat = 18
    /// 指示条下方的留白。
    static let bottomPadding: CGFloat = 6
}

/// 视频正下方的选项栏，切换简介和评论。
///
/// 这是 B 站官方客户端和 PiliPlus 的做法：选项栏跟着视频走，不去占用屏幕底部，
/// 也就不会和首页那条系统标签栏产生任何关系。
/// 选中项下方有一条会滑动的指示条，滑动切换页面时它跟着一起动。
struct VideoSectionBar: View {
    @Binding var selection: VideoPageSection
    /// 评论总数，跟在「评论」后面显示。还没加载出来（为 0）时不显示，
    /// 免得先出现一个 0 再跳成真实数字。
    var commentCount: Int = 0

    /// 指示条靠它在两个选项之间做滑动动画，而不是在旧位置消失、新位置出现。
    @Namespace private var indicatorNamespace

    var body: some View {
        // 每一项各占一半宽度并居中，两个标签因此左右对称。
        HStack(spacing: 0) {
            ForEach(VideoPageSection.allCases) { section in
                item(section)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, VideoSectionBarLayout.topPadding)
        .padding(.bottom, VideoSectionBarLayout.bottomPadding)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    private func item(_ section: VideoPageSection) -> some View {
        let isSelected = selection == section

        return Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                selection = section
            }
        } label: {
            VStack(spacing: VideoSectionBarLayout.textIndicatorSpacing) {
                Text(title(for: section))
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)

                // 未选中的那一项也占着同样高度的空位，切换时文字不会上下跳动。
                Capsule()
                    .fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear))
                    .frame(
                        width: VideoSectionBarLayout.indicatorWidth,
                        height: VideoSectionBarLayout.indicatorHeight
                    )
                    .modifier(SlidingIndicator(isSelected: isSelected, namespace: indicatorNamespace))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title(for: section))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func title(for section: VideoPageSection) -> String {
        guard section == .comments, commentCount > 0 else { return section.title }
        return "\(section.title) \(commentCount.biliCountText)"
    }
}

/// 只给选中的那一条指示条挂上共享标识，SwiftUI 就会把它从旧位置滑到新位置。
private struct SlidingIndicator: ViewModifier {
    let isSelected: Bool
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        if isSelected {
            content.matchedGeometryEffect(id: "video-section-indicator", in: namespace)
        } else {
            content
        }
    }
}
