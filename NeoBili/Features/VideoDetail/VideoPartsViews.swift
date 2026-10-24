#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI

/// 简介里的分P入口。和合集（`UgcSeasonRow`）同一套显示与交互：
/// 折叠成一行，右侧标「当前第几P / 共几P」，点开弹分P列表。
struct VideoPartsRow: View {
    let currentPartName: String
    let total: Int
    /// 当前正在播放的分P序号（从 1 开始）。找不到时不显示序号。
    let currentIndex: Int?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Label("分P · \(currentPartName)", systemImage: "list.number")
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(progressText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("分P，\(progressText)，展开分P列表")
    }

    private var progressText: String {
        guard let currentIndex else { return "\(total)" }
        return "P\(currentIndex)/\(total)"
    }
}

/// 分P以独立视频卡片展示，直接铺在页面背景上。
struct VideoPartsSheet: View {
    let parts: [VideoPart]
    let currentCid: Int?
    var coverURL: URL? = nil
    let onSelect: (VideoPart) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(parts) { part in
                        Button {
                            onSelect(part)
                        } label: {
                            VideoListCard(
                                coverURL: coverURL,
                                title: part.part,
                                author: part.cid == currentCid ? String(localized: "P\(part.page) · 正在播放") : "P\(part.page)",
                                playCount: -1,
                                durationText: part.formattedDuration
                            )
                        }
                        .buttonStyle(.plain)
                        .videoPickerSelection(part.cid == currentCid)
                        .padding(.horizontal, VideoListCardLayout.pageHorizontalInset)
                        .padding(.vertical, VideoListCardLayout.cardVerticalSpacing)
                        .id(part.id)
                    }
                }
                .scrollTargetLayout()
            }
            .videoPickerInitialPosition(target: parts.first(where: { $0.cid == currentCid })?.id)
            .background(Color(uiColor: .systemGroupedBackground))
            .leftEdgeTapDeadZone()
            .navigationTitle("分P")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        // The list's background does not replace the sheet's own live glass
        // backdrop. Keep the half-height picker opaque above a playing video.
        .presentationBackground(Color(uiColor: .systemGroupedBackground))
        .videoCardAnimationSource(.collection)
    }
}

/// Position is owned by each presented picker. User scrolling does not change
/// the playback target, so routine redraws never pull the list back to it.
private struct VideoPickerInitialPosition<ID: Hashable & Sendable>: ViewModifier {
    let target: ID?
    @State private var hasPositioned = false

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .task(id: target) {
                    guard !hasPositioned, let target else { return }
                    // Let the lazy stack register its row IDs before requesting
                    // the initial position; no timed animation or delayed jump.
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                    hasPositioned = true
                }
        }
    }
}

private struct VideoPickerSelection: ViewModifier {
    let selected: Bool
    @Environment(\.appThemeColor) private var themeColor

    func body(content: Content) -> some View {
        content
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: VideoListCardLayout.cardCornerRadius)
                        .fill(themeColor.opacity(0.12))
                        .overlay {
                            RoundedRectangle(cornerRadius: VideoListCardLayout.cardCornerRadius)
                                .strokeBorder(themeColor, lineWidth: 1.5)
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier(selected ? "video-picker.current" : "video-picker.item")
    }
}

extension View {
    func videoPickerInitialPosition<ID: Hashable & Sendable>(target: ID?) -> some View {
        modifier(VideoPickerInitialPosition(target: target))
    }

    func videoPickerSelection(_ selected: Bool) -> some View {
        modifier(VideoPickerSelection(selected: selected))
    }
}

/// 合集、分P 面板的弹出条件本身就是要展示的内容，用 `sheet(item:)` 呈现。
/// 用「先存内容、再翻开关」的 `sheet(isPresented:)` 时，第一次弹出可能沿用
/// 内容为空时的渲染，面板会整片空白；内容随弹出条件一起传入就不会读到旧值。
/// 每次点击都是新的一次呈现，所以标识用新的 UUID。
struct VideoPickerPresentation<Content>: Identifiable {
    let id = UUID()
    let content: Content
}

/// 分P 面板打开时取好的列表和封面；切换分P 期间列表保持不变，当前分P 仍跟随播放状态。
struct VideoPartsPickerContent {
    let parts: [VideoPart]
    let coverURL: URL?
}

struct VideoPartsPlaybackSheet: View {
    let parts: [VideoPart]
    let coverURL: URL?
    @Environment(NowPlayingStore.self) private var store

    var body: some View {
        VideoPartsSheet(parts: parts, currentCid: store.activeCid, coverURL: coverURL) { part in
            store.selectPart(cid: part.cid)
            store.requestPlayback()
        }
    }
}
