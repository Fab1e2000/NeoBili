import SwiftUI

/// 简介里的分P入口。和合集（`UgcSeasonRow`）同一套显示与交互：
/// 折叠成一行，右侧标「当前第几P / 共几P」，点开弹分P列表。
struct VideoPartsRow: View {
    let parts: [VideoPart]
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
        }
        .buttonStyle(.glass)
        .tint(.primary)
        .controlSize(.large)
        .accessibilityLabel("分P，\(progressText)，展开分P列表")
    }

    private var currentPartName: String {
        guard let currentIndex, parts.indices.contains(currentIndex - 1) else {
            return "视频分集"
        }
        return parts[currentIndex - 1].part
    }

    private var progressText: String {
        let total = parts.count
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
                            dismiss()
                        } label: {
                            VideoListCard(
                                coverURL: coverURL,
                                title: part.part,
                                author: part.cid == currentCid ? "P\(part.page) · 正在播放" : "P\(part.page)",
                                playCount: -1,
                                durationText: part.formattedDuration
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(part.cid == currentCid ? .isSelected : [])
                        .padding(.horizontal, VideoListCardLayout.pageHorizontalInset)
                        .padding(.vertical, VideoListCardLayout.cardVerticalSpacing)
                    }
                }
            }
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
        .videoCardAnimationSource(.collection)
    }
}
