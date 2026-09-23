import SwiftUI

/// 标题栏随内容滚动时，直播页推荐/关注两页共用的页头状态。
///
/// 做法参考 JXPagingView、Twitter 个人页这类「可收起页头 + 吸顶分段 + 横向分页列表」：
/// 页头只有一份，放在横向分页之外；每页列表顶部留出页头高度，页头的纵向位置跟随
/// 当前页的滚动——先收起标题，切换器到顶后吸附。另一页的滚动位置随之联动，
/// 左右翻页时页头不会跳。
///
/// 单独一个可观察对象：逐帧变化只让页头和联动逻辑重算，不牵动两页列表。
@MainActor @Observable
final class LiveHeaderState {
    /// 标题行高度，也是页头最多能收起的距离；收起到这里切换器吸顶。
    var titleHeight: CGFloat = 60
    /// 整个页头（标题 + 切换器）的高度，两页列表顶部各留出这么多。
    var height: CGFloat = 112
    /// 当前页已收起的距离，0...titleHeight。下拉时保持 0，页头停在原位。
    var collapse: CGFloat = 0
}

/// 浮在两页列表上方的页头：标题随当前页上滑收起，切换器最终吸在顶部。
struct LiveCollapsingHeader<Title: View, Picker: View>: View {
    let state: LiveHeaderState
    @ViewBuilder let title: Title
    @ViewBuilder let picker: Picker

    var body: some View {
        VStack(spacing: 0) {
            title
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { state.titleHeight = $0 }
            picker
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { state.height = $0 }
        .offset(y: -state.collapse)
        // 收起的标题在安全区上缘被裁掉，滑到状态栏下面由系统的顶部模糊接管。
        .frame(maxWidth: .infinity, alignment: .top)
        .clipped()
    }
}

extension View {
    /// 挂在直播每一页的滚动视图上：为共享页头留出顶部位置，当前页上报收起距离，
    /// 另一页按「列表联动」规则跟随。`state` 为 nil（标题栏固定）时不做任何事。
    func liveCollapsingHeaderScroll(state: LiveHeaderState?, isActive: Bool,
                                    position: Binding<ScrollPosition>) -> some View {
        modifier(LiveCollapsingHeaderScroll(state: state, isActive: isActive, position: position))
    }
}

private struct LiveCollapsingHeaderScroll: ViewModifier {
    let state: LiveHeaderState?
    let isActive: Bool
    @Binding var position: ScrollPosition
    /// 本页离顶部滚了多远。只在联动时读取，不参与界面更新。
    @State private var offset = OffsetBox()

    private final class OffsetBox { var value: CGFloat = 0 }

    func body(content: Content) -> some View {
        if let state {
            content
                .contentMargins(.top, state.height, for: .scrollContent)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, newOffset in
                    offset.value = newOffset
                    guard isActive else { return }
                    let collapse = min(max(newOffset, 0), state.titleHeight)
                    if state.collapse != collapse { state.collapse = collapse }
                }
                .onChange(of: state.collapse) { _, collapse in
                    guard !isActive else { return }
                    follow(collapse, titleHeight: state.titleHeight)
                }
                .onChange(of: isActive) { _, active in
                    // 刚翻到这一页：以它自己的位置为准更新页头（联动后两者一致，不会跳）。
                    if active { state.collapse = min(max(offset.value, 0), state.titleHeight) }
                }
        } else {
            content
        }
    }

    /// 列表联动：页头还没收起完时，另一页停在同样的位置；已经收起（切换器吸顶）时，
    /// 另一页至少滚到刚好收起的位置，已经滚得更远的保持不动。
    private func follow(_ collapse: CGFloat, titleHeight: CGFloat) {
        let target = collapse < titleHeight ? collapse : max(offset.value, titleHeight)
        guard abs(target - offset.value) > 0.5 else { return }
        offset.value = target
        position.scrollTo(y: target)
    }
}
