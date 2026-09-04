import SwiftUI

/// 关注页顶部的 Cover Flow 头像轮盘。它只管视觉焦点与滚动手感，
/// 真正的动态数据切换由父视图在滚动停稳后处理。
struct FollowingCarousel: View {
    let items: [FollowingSelection]
    @Binding var focusedID: FollowingSelection.ID
    let onSettled: (FollowingSelection.ID) -> Void
    let onOpenUp: (FollowedUp) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var allowsHaptics = false
    @State private var isSynchronizingItems = false
    @State private var isUserScrollSession = false
    /// 系统滚动过程中持续写入的实际居中项。如果直接把 focusedID 挂在
    /// scrollPosition 上，快速甩动时每次经过的项都会改写焦点并立刻反向
    /// 拉扯滚动目标，减速被中途打断，最终停在两格之间无法对齐中轴。
    @State private var positionID: FollowingSelection.ID?
    /// 对齐看门狗：快速甩动后系统偶发停在两格之间且不触发任何回调，
    /// 选中项稳定 0.3 秒后由它强制把轮盘重新对位回中轴。
    @State private var snapTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: FollowingCarouselLayout.titleSpacing) {
            GeometryReader { geometry in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: FollowingCarouselLayout.itemSpacing) {
                        ForEach(items) { item in
                            wheelItem(item)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(
                    .horizontal,
                    max((geometry.size.width - FollowingCarouselLayout.itemWidth) / 2, 0),
                    for: .scrollContent
                )
                .scrollPosition(id: $positionID, anchor: .center)
                // 紧凑宽度下系统默认会限制一次滑过的项数；轮盘需要保留
                // 连续甩动的惯性，最后仍由 viewAligned 对齐到中央头像。
                .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
                .scrollIndicators(.hidden)
                .onScrollPhaseChange { _, newPhase in
                    switch newPhase {
                    case .tracking, .interacting:
                        isUserScrollSession = true
                        snapTask?.cancel()
                    case .idle:
                        guard isUserScrollSession else { return }
                        isUserScrollSession = false
                        settleIfNeeded()
                    case .decelerating, .animating:
                        break
                    }
                }
            }
            .frame(height: FollowingCarouselLayout.wheelHeight)

            Text(focusedItem?.title ?? "全部动态")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.opacity)
                .accessibilityHidden(true)
        }
        .frame(height: FollowingCarouselLayout.totalHeight)
        .onAppear {
            positionID = focusedID
            Task { @MainActor in
                await Task.yield()
                allowsHaptics = true
            }
            scheduleAlignmentSnap()
        }
        .onDisappear {
            snapTask?.cancel()
        }
        .onChange(of: items.map(\.id)) { _, itemIDs in
            guard itemIDs.contains(focusedID) else {
                synchronizeFocus(to: .all)
                return
            }
        }
        .onChange(of: positionID) { _, newID in
            // 用户滚动时让焦点描边实时跟随居中的头像；此时 focusedID 的变化
            // 不会再回流到 scrollPosition，因此不会打断减速惯性。
            if isUserScrollSession, let newID, newID != focusedID {
                focusedID = newID
            }
        }
        .onChange(of: focusedID) { _, newID in
            // 程序化变更焦点（点击、数据同步）时驱动轮盘对位到新的中央项。
            if positionID != newID, items.contains(where: { $0.id == newID }) {
                if isSynchronizingItems {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { positionID = newID }
                } else {
                    withAnimation(.snappy(duration: 0.28, extraBounce: 0.08)) {
                        positionID = newID
                    }
                }
            }
            scheduleAlignmentSnap()
        }
        .sensoryFeedback(.selection, trigger: focusedID) { oldValue, newValue in
            allowsHaptics
                && !isSynchronizingItems
                && oldValue != newValue
        }
    }

    /// SwiftUI 会在横向轮盘被外层 LazyVStack 回收、重新出现时把
    /// scrollPosition 写成 nil；只有真实的横向手势停稳后才允许把滚动
    /// 落点同步为逻辑焦点，纵向滚动造成的布局同步不能改变当前筛选。
    private func settleIfNeeded() {
        guard let positionID else {
            onSettled(focusedID)
            return
        }
        if positionID != focusedID {
            focusedID = positionID
        }
        onSettled(positionID)
        scheduleAlignmentSnap()
    }

    /// 选中项保持焦点 10 毫秒后仍可能视觉上偏离中轴（系统减速落点偶尔
    /// 停在两个头像之间，且此时不会再有任何滚动回调）。到点后无条件
    /// 重新对位一次：已对齐时无感知，未对齐时平滑修正。
    private func scheduleAlignmentSnap() {
        snapTask?.cancel()
        guard items.contains(where: { $0.id == focusedID }) else { return }
        let target = focusedID
        snapTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(10))
            guard !Task.isCancelled, !isUserScrollSession else { return }
            forceAlign(to: target)
        }
    }

    /// 重新写入相同的 positionID 不会触发滚动，必须先置 nil 落定一帧，
    /// 再写回目标 id 才能让 ScrollView 以 .center 锚点重新吸附中轴。
    private func forceAlign(to id: FollowingSelection.ID) {
        positionID = nil
        Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, !isUserScrollSession else { return }
            withAnimation(.snappy(duration: 0.3, extraBounce: 0.05)) {
                positionID = id
            }
        }
    }

    private var focusedItem: FollowingSelection? {
        return items.first { $0.id == focusedID }
    }

    private func wheelItem(_ item: FollowingSelection) -> some View {
        let isFocused = focusedID == item.id
        let rotation = reduceMotion ? 0.0 : FollowingCarouselLayout.sideRotation
        return FollowingCarouselItem(item: item, isFocused: isFocused) {
            handleTap(item, isFocused: isFocused)
        }
        .frame(
            width: FollowingCarouselLayout.itemWidth,
            height: FollowingCarouselLayout.itemHeight
        )
        .id(item.id)
        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
            content
                .scaleEffect(FollowingCarouselLayout.scale(for: phase.value))
                .opacity(FollowingCarouselLayout.opacity(for: phase.value))
                .rotation3DEffect(
                    .degrees(Double(phase.value) * rotation),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: FollowingCarouselLayout.perspective
                )
                .offset(y: FollowingCarouselLayout.drop(for: phase.value))
        }
    }

    private func handleTap(_ item: FollowingSelection, isFocused: Bool) {
        if isFocused {
            if let up = item.up {
                onOpenUp(up)
            }
        } else {
            withAnimation(.snappy(duration: 0.28, extraBounce: 0.08)) {
                focusedID = item.id
            } completion: {
                onSettled(item.id)
            }
        }
    }

    private func synchronizeFocus(to id: FollowingSelection.ID) {
        isSynchronizingItems = true
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            focusedID = id
        }
        onSettled(id)

        Task { @MainActor in
            await Task.yield()
            isSynchronizingItems = false
        }
    }
}

/// 独立子视图让轮盘滚动时只重绘焦点附近的头像，也避免一条过长的
/// SwiftUI 修饰链拖慢编译器。
private struct FollowingCarouselItem: View {
    let item: FollowingSelection
    let isFocused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            avatar
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(item.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(isFocused ? .isSelected : [])
    }

    private var accessibilityValue: String {
        if isFocused {
            item.up?.hasUpdate == true ? "已选中，有新动态" : "已选中"
        } else {
            item.up?.hasUpdate == true ? "有新动态" : ""
        }
    }

    private var accessibilityHint: String {
        isFocused && item.up != nil ? "轻点打开 UP 主个人主页" : "轻点转到轮盘中央"
    }

    private var avatar: some View {
        ZStack {
            if let up = item.up {
                BiliImage(url: up.secureAvatarURL)
                    .aspectRatio(contentMode: .fill)
            } else {
                AllDynamicsAvatar()
            }
        }
        .frame(width: FollowingCarouselLayout.avatarSize, height: FollowingCarouselLayout.avatarSize)
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(
                    isFocused ? Color.accentColor : Color.white.opacity(0.35),
                    lineWidth: isFocused ? 2.5 : 1
                )
        }
        .shadow(
            color: .black.opacity(isFocused ? 0.18 : 0.08),
            radius: isFocused ? 8 : 3,
            y: isFocused ? 4 : 2
        )
        .overlay(alignment: .topTrailing) {
            if item.up?.hasUpdate == true {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .overlay {
                        Circle().stroke(Color(uiColor: .systemGroupedBackground), lineWidth: 2)
                    }
                    .accessibilityHidden(true)
                }
            }
        }
    }
/// 「全部动态」使用的代码原生品牌头像：三条轨道与节点表示多个 UP
/// 共同组成一条动态流，不依赖额外位图资源。
private struct AllDynamicsAvatar: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.62)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            ZStack {
                orbit(width: 40, height: 17, rotation: 24)
                orbit(width: 40, height: 17, rotation: -24)
                orbit(width: 20, height: 39, rotation: 0)

                Circle()
                    .fill(.white)
                    .frame(width: 7, height: 7)

                Circle()
                    .fill(.white)
                    .frame(width: 5, height: 5)
                    .offset(x: 17, y: -7)

                Circle()
                    .fill(.white.opacity(0.9))
                    .frame(width: 4, height: 4)
                    .offset(x: -14, y: 11)
            }
        }
    }

    private func orbit(width: CGFloat, height: CGFloat, rotation: Double) -> some View {
        Ellipse()
            .stroke(.white.opacity(0.82), lineWidth: 1.6)
            .frame(width: width, height: height)
            .rotationEffect(.degrees(rotation))
    }
}

private enum FollowingCarouselLayout {
    static let avatarSize: CGFloat = 68
    /// 约 400pt 的屏幕一次展示七个轮盘槽位；中央头像仍保持 68pt，
    /// 让相邻头像轻微交叠，形成更紧凑的 Cover Flow 层次。
    static let itemWidth: CGFloat = 56
    static let itemHeight: CGFloat = 82
    static let itemSpacing: CGFloat = 0
    static let wheelHeight: CGFloat = 88
    static let titleSpacing: CGFloat = 5
    static let totalHeight: CGFloat = 122
    static let sideScaleLoss: CGFloat = 0.24
    static let sideOpacityLoss: CGFloat = 0.48
    static let sideRotation = 45.0
    static let perspective: CGFloat = 0.5
    static let sideDrop: CGFloat = 8

    static func scale(for phase: CGFloat) -> CGFloat {
        1 - min(abs(phase), 1) * sideScaleLoss
    }

    static func opacity(for phase: CGFloat) -> CGFloat {
        1 - min(abs(phase), 1) * sideOpacityLoss
    }

    static func drop(for phase: CGFloat) -> CGFloat {
        min(abs(phase), 1) * sideDrop
    }
}

#Preview("Cover Flow") {
    FollowingCarouselPreview()
        .background(Color(uiColor: .systemGroupedBackground))
}

private struct FollowingCarouselPreview: View {
    @State private var focusedID: FollowingSelection.ID = .all

    private let items: [FollowingSelection] = [
        .all,
        .up(FollowedUp(mid: 1, uname: "影视飓风", face: "", hasUpdate: true)),
        .up(FollowedUp(mid: 2, uname: "罗翔说刑法", face: "", hasUpdate: false)),
        .up(FollowedUp(mid: 3, uname: "老番茄", face: "", hasUpdate: true)),
        .up(FollowedUp(mid: 4, uname: "科普中国", face: "", hasUpdate: false))
    ]

    var body: some View {
        FollowingCarousel(
            items: items,
            focusedID: $focusedID,
            onSettled: { _ in },
            onOpenUp: { _ in }
        )
    }
}
