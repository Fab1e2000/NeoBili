import SwiftUI
import UIKit

/// A：边缘头像入口；B：可上下滚动的头像列表。仅在停稳或收起时提交筛选。
struct FollowingCarousel: View {
    @Environment(\.videoTransitionNamespace) private var videoTransition
    let items: [FollowingSelection]
    @Binding var focusedID: FollowingSelection.ID
    let side: FollowingSidebarSide
    @Binding var isExpanded: Bool
    let onSettled: (FollowingSelection.ID) -> Void
    let onOpenUp: (FollowedUp) -> Void
    let onOpenLive: (FollowedUp) -> Void
    let onContextMenuChange: (Bool) -> Void
    let interactiveProgress: CGFloat?
    let motion: FollowingSidebarMotion?
    let onCloseSwipe: (CGFloat) -> Void
    let onCloseSwipeEnd: (CGFloat) -> Void

    // 每次打开独立的滚动会话，旧 ScrollView 的退出回调不能改变新会话。
    @State private var sessionID = UUID()
    @State private var expandedIDs: [FollowingSelection.ID] = []
    @AppStorage(FollowingSidebarLayout.countKey) private var visibleCount = FollowingSidebarLayout.defaultCount
    @State private var isPressSelecting = false
    @State private var isBackdropDragging = false
    @State private var isBackdropClosing = false
    @State private var scrollController: FollowingAvatarScrollController

    init(items: [FollowingSelection], focusedID: Binding<FollowingSelection.ID>, side: FollowingSidebarSide,
         isExpanded: Binding<Bool>, onSettled: @escaping (FollowingSelection.ID) -> Void,
         onOpenUp: @escaping (FollowedUp) -> Void,
         onOpenLive: @escaping (FollowedUp) -> Void = { _ in },
         onContextMenuChange: @escaping (Bool) -> Void = { _ in },
         interactiveProgress: CGFloat? = nil,
         motion: FollowingSidebarMotion? = nil,
         onCloseSwipe: @escaping (CGFloat) -> Void = { _ in },
         onCloseSwipeEnd: @escaping (CGFloat) -> Void = { _ in },
         controller: FollowingAvatarScrollController? = nil) {
        self.items = items
        _focusedID = focusedID
        self.side = side
        _isExpanded = isExpanded
        self.onSettled = onSettled
        self.onOpenUp = onOpenUp
        self.onOpenLive = onOpenLive
        self.onContextMenuChange = onContextMenuChange
        self.interactiveProgress = interactiveProgress
        self.motion = motion
        self.onCloseSwipe = onCloseSwipe
        self.onCloseSwipeEnd = onCloseSwipeEnd
        _scrollController = State(initialValue: controller ?? FollowingAvatarScrollController())
    }

    private var displayedItems: [FollowingSelection] {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let known = Set(expandedIDs)
        let stable = expandedIDs.compactMap { byID[$0] } + items.filter { !known.contains($0.id) }
        return stable.filter { $0.id == .all }
            + stable.filter { $0.up?.liveRoomID != nil }
            + stable.filter { $0.id != .all && $0.up?.liveRoomID == nil }
    }

    private var focusedItem: FollowingSelection {
        items.first { $0.id == focusedID } ?? .all
    }

    var body: some View {
        GeometryReader { geometry in
            let height = FollowingSidebarLayout.height(count: visibleCount, available: geometry.size.height)
            let rowHeight = height / CGFloat(FollowingSidebarLayout.count(visibleCount))
            ZStack(alignment: side.alignment) {
                if isExpanded {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 8, coordinateSpace: .global)
                                .onChanged { value in
                                    let translation = value.translation.width * (side == .left ? 1 : -1)
                                    if !isBackdropDragging,
                                       isBackdropClosing || (translation < 0 && abs(translation) > abs(value.translation.height) * 1.3) {
                                        isBackdropClosing = true
                                        onCloseSwipe(translation)
                                        return
                                    }
                                    guard isBackdropDragging || abs(value.translation.height) > abs(value.translation.width) else { return }
                                    if !isBackdropDragging {
                                        isBackdropDragging = true
                                        scrollController.beginExternalDrag()
                                    }
                                    scrollController.moveExternalDrag(
                                        translation: value.translation.height,
                                        velocity: value.velocity.height
                                    )
                                }
                                .onEnded { value in
                                    if isBackdropClosing {
                                        isBackdropClosing = false
                                        onCloseSwipe(value.translation.width * (side == .left ? 1 : -1))
                                        onCloseSwipeEnd(value.velocity.width * (side == .left ? 1 : -1))
                                        return
                                    }
                                    guard isBackdropDragging else { return }
                                    scrollController.endExternalDrag()
                                    isBackdropDragging = false
                                }
                                .exclusively(before: TapGesture().onEnded { collapse() })
                        )
                        .accessibilityLabel("收起关注列表")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { collapse() }
                        .accessibilityIdentifier("following.sidebar.dismiss")

                }
                // 同一份原生列表同时承载 A/B，收起不会销毁或复制头像。
                expandedRail(height: height, rowHeight: rowHeight)
                    .videoTransitionSource("following-live", in: videoTransition)
                    .allowsHitTesting(isExpanded)
                    .accessibilityHidden(!isExpanded)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 12, coordinateSpace: .global)
                            .onChanged { value in
                                let translation = value.translation.width * (side == .left ? 1 : -1)
                                guard isExpanded,
                                      isBackdropClosing || (translation < 0 && abs(translation) > abs(value.translation.height) * 1.3) else { return }
                                isBackdropClosing = true
                                onCloseSwipe(translation)
                            }
                            .onEnded { value in
                                guard isBackdropClosing else { return }
                                isBackdropClosing = false
                                onCloseSwipe(value.translation.width * (side == .left ? 1 : -1))
                                onCloseSwipeEnd(value.velocity.width * (side == .left ? 1 : -1))
                            }
                    )
                ZStack {
                    FollowingHandleTouchSurface(
                        enabled: !isExpanded || isPressSelecting,
                        onBegin: {
                            expand()
                            isPressSelecting = true
                            scrollController.beginExternalDrag()
                        },
                        onMove: { delta, velocity in
                            scrollController.moveExternalDrag(translation: delta, velocity: velocity)
                        },
                        onEnd: {
                            scrollController.endExternalDrag()
                            isPressSelecting = false
                        }
                    )
                }
                .frame(width: 44, height: 76)
                .allowsHitTesting(!isExpanded || isPressSelecting)
                .accessibilityHidden(isExpanded)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("展开关注列表，\(focusedItem.title)")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { expand() }
                .accessibilityIdentifier("following.sidebar.expand")

            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: side.alignment)
            .clipped()
        }
        .onChange(of: items.map(\.id)) { _, ids in
            if !ids.contains(focusedID) {
                focusedID = .all
                // 被取消关注的选中项消失时重建会话，以「全部」重新定位。
                sessionID = UUID()
                onSettled(.all)
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                expandedIDs = items.map(\.id)
            } else {
                isBackdropDragging = false
                isBackdropClosing = false
                isPressSelecting = false
                scrollController.stop()
            }
        }
    }

    private func expandedRail(height: CGFloat, rowHeight: CGFloat) -> some View {
        let session = sessionID
        return FollowingExpandedCarousel(
            items: displayedItems,
            initialID: focusedID,
            side: side,
            height: height,
            rowHeight: rowHeight,
            isExpanded: isExpanded,
            interactiveProgress: interactiveProgress,
            motion: motion,
            controller: scrollController,
            onFocus: { id in
                guard isExpanded, sessionID == session else { return }
                focusedID = id
            },
            onSettled: { id in
                guard isExpanded, sessionID == session else { return }
                onSettled(id)
            },
            onOpenUp: { up in
                collapse()
                onOpenUp(up)
            },
            onOpenLive: { up in
                collapse()
                onOpenLive(up)
            },
            onContextMenuChange: onContextMenuChange
        )
        .id(session)
    }

    private func expand() {
        guard !isExpanded else { return }
        expandedIDs = items.map(\.id)
        isExpanded = true
    }

    private func collapse() {
        onSettled(focusedID)
        isExpanded = false
    }
}

/// 原生列表负责唯一一份头像布局；玻璃只放在背景，不参与头像变换。
private struct FollowingExpandedCarousel: View {
    let items: [FollowingSelection]
    let initialID: FollowingSelection.ID
    let side: FollowingSidebarSide
    let height: CGFloat
    let rowHeight: CGFloat
    let isExpanded: Bool
    let interactiveProgress: CGFloat?
    let motion: FollowingSidebarMotion?
    let controller: FollowingAvatarScrollController
    let onFocus: (FollowingSelection.ID) -> Void
    let onSettled: (FollowingSelection.ID) -> Void
    let onOpenUp: (FollowedUp) -> Void
    let onOpenLive: (FollowedUp) -> Void
    let onContextMenuChange: (Bool) -> Void
    @State private var titleID: FollowingSelection.ID?
    @State private var alignmentDistance: CGFloat?
    @State private var isContextMenuPresented = false

    var body: some View {
        let shape = FollowingSidebarShape(side: side)
        let progress = motion?.progress ?? interactiveProgress
        GlassEffectContainer(spacing: 0) {
            FollowingAvatarScroll(
                items: items, initialID: initialID, side: side, rowHeight: rowHeight,
                isExpanded: isExpanded, interactiveProgress: progress, controller: controller,
                onFocus: { titleID = $0; onFocus($0) },
                onSettled: onSettled, onOpenUp: onOpenUp,
                onOpenLive: onOpenLive,
                onContextMenuChange: {
                    isContextMenuPresented = $0
                    onContextMenuChange($0)
                },
                onAlignment: { alignmentDistance = $0 }
            )
            .frame(width: FollowingSidebarShape.width, height: height)
            .contentShape(shape)
            .overlay(alignment: side == .left ? .trailing : .leading) {
                if isExpanded && !isContextMenuPresented {
                    Text(items.first { $0.id == (titleID ?? initialID) }?.title ?? "全部动态")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .glassEffect(.regular, in: Capsule())
                        .frame(width: 140)
                        .opacity(Double(progress ?? 1))
                        .offset(x: side == .left ? 144 : -144)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .preference(key: FollowingSidebarAlignmentKey.self, value: alignmentDistance)
            .accessibilityIdentifier("following.sidebar.list")
        }
    }
}

/// 零等待触摸识别：从按下到松手始终由同一个 UIView 接收。
private struct FollowingHandleTouchSurface: UIViewRepresentable {
    let enabled: Bool
    let onBegin: () -> Void
    let onMove: (CGFloat, CGFloat) -> Void
    let onEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.press(_:)))
        press.minimumPressDuration = 0
        press.allowableMovement = 16
        view.addGestureRecognizer(press)
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
        view.isUserInteractionEnabled = enabled
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: FollowingHandleTouchSurface
        var startY: CGFloat = 0
        var previousY: CGFloat = 0
        var previousTime: CFTimeInterval = 0
        init(_ parent: FollowingHandleTouchSurface) { self.parent = parent }
        @objc func press(_ gesture: UILongPressGestureRecognizer) {
            let y = gesture.location(in: gesture.view?.window).y
            let now = CACurrentMediaTime()
            switch gesture.state {
            case .began:
                startY = y
                previousY = y
                previousTime = now
                parent.onBegin()
            case .changed:
                let elapsed = max(now - previousTime, 0.001)
                parent.onMove(y - startY, (y - previousY) / elapsed)
                previousY = y
                previousTime = now
            case .ended, .cancelled, .failed:
                // 停住后松手不应继承之前甩动的速度。
                if now - previousTime > 0.1 { parent.onMove(y - startY, 0) }
                parent.onEnd()
            default: break
            }
        }
    }
}
