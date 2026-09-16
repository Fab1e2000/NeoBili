import SwiftUI

/// 简介里的合集入口：折叠成一行，点开才列出全部分集。
///
/// 合集动辄几十上百集，直接铺在简介里会把相关视频推到很远的地方；官方也是
/// 折叠一行的做法，右侧标出「当前第几集 / 共几集」。
struct UgcSeasonRow: View {
    let season: UgcSeason
    /// 当前正在播放的分集在合集里的序号（从 1 开始）。找不到时不显示序号。
    let currentIndex: Int?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Label("合集 · \(season.title ?? "")", systemImage: "rectangle.stack")
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
        .accessibilityLabel("合集 \(season.title ?? "")，\(progressText)，展开分集列表")
    }

    private var progressText: String {
        let total = season.episodes.count
        guard let currentIndex else { return "\(total)" }
        return "\(currentIndex)/\(total)"
    }
}

/// 合集分集使用与搜索结果一致的独立卡片。
struct UgcSeasonSheet: View {
    let season: UgcSeason
    /// 当前播放的稿件 bvid，用来高亮。
    let currentBvid: String?
    let onSelect: (UgcSeasonEpisode) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.hidesPortraitVideos) private var hidesPortraitVideos

    private var visibleEpisodes: [UgcSeasonEpisode] {
        season.episodes.hidingKnownPortraitVideos(hidesPortraitVideos)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if visibleEpisodes.isEmpty, season.episodes.hasPendingVideoDimensions(hidesPortraitVideos) {
                        LoadingTaskAnchor()
                    } else if visibleEpisodes.isEmpty {
                        ContentUnavailableView("没有可显示的分集", systemImage: "rectangle.slash")
                    } else {
                        ForEach(visibleEpisodes) { episode in
                            Button {
                                onSelect(episode)
                                dismiss()
                            } label: {
                                VideoListCard(
                                    coverURL: episode.secureCoverURL,
                                    title: episode.title ?? "",
                                    author: episode.bvid == currentBvid ? "正在播放" : (season.title ?? "合集"),
                                    playCount: -1,
                                    durationText: episode.formattedDuration
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(episode.bvid == currentBvid ? .isSelected : [])
                            .padding(.horizontal, VideoListCardLayout.pageHorizontalInset)
                            .padding(.vertical, VideoListCardLayout.cardVerticalSpacing)
                        }
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            // 左缘触控死区：防止边缘误触直接切了分集。
            .leftEdgeTapDeadZone()
            .navigationTitle(season.title ?? "合集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .resolvePortraitVideos(season.episodes)
        .videoCardAnimationSource(.collection)
    }
}
