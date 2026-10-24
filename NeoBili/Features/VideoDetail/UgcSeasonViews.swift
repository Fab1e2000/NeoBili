#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI

/// 简介里的合集入口：折叠成一行，点开才列出全部分集。
///
/// 合集动辄几十上百集，直接铺在简介里会把相关视频推到很远的地方；官方也是
/// 折叠一行的做法，右侧标出「当前第几集 / 共几集」。
struct UgcSeasonRow: View {
    let title: String
    let total: Int
    /// 当前正在播放的分集在合集里的序号（从 1 开始）。找不到时不显示序号。
    let currentIndex: Int?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Label(String(localized: "合集 · \(title)"), systemImage: "rectangle.stack")
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
        .accessibilityLabel(String(localized: "合集 \(title)，\(progressText)，展开分集列表"))
    }

    private var progressText: String {
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
    @Environment(\.videoFiltering) private var filtering
    @Environment(\.hidesPortraitVideos) private var hidesPortraitVideos

    var body: some View {
        let episodes = season.episodes
        let visibleEpisodes = episodes.hidingKnownPortraitVideos(hidesPortraitVideos, filtering: filtering)
        let currentID = currentBvid.flatMap { bvid in visibleEpisodes.first { $0.bvid == bvid }?.id }
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if visibleEpisodes.isEmpty, episodes.hasPendingVideoDimensions(hidesPortraitVideos, filtering: filtering) {
                        LoadingTaskAnchor()
                    } else if visibleEpisodes.isEmpty {
                        ContentUnavailableView("没有可显示的分集", systemImage: "rectangle.slash")
                    } else {
                        ForEach(visibleEpisodes) { episode in
                            Button {
                                onSelect(episode)
                            } label: {
                                VideoListCard(
                                    coverURL: episode.secureCoverURL,
                                    title: episode.title ?? "",
                                    author: episode.id == currentID ? String(localized: "正在播放") : (season.title ?? String(localized: "合集")),
                                    playCount: -1,
                                    durationText: episode.formattedDuration
                                )
                            }
                            .buttonStyle(.plain)
                            .videoPickerSelection(episode.id == currentID)
                            .padding(.horizontal, VideoListCardLayout.pageHorizontalInset)
                            .padding(.vertical, VideoListCardLayout.cardVerticalSpacing)
                            .id(episode.id)
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .videoPickerInitialPosition(target: currentID)
            .background(Color(uiColor: .systemGroupedBackground))
            // 左缘触控死区：防止边缘误触直接切了分集。
            .leftEdgeTapDeadZone()
            .navigationTitle(season.title ?? String(localized: "合集"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        // Match the parts picker: avoid a live glass backdrop over Metal video
        // while retaining the native half/full-height sheet and ongoing playback.
        .presentationBackground(Color(uiColor: .systemGroupedBackground))
        .resolvePortraitVideos(episodes)
        .videoCardAnimationSource(.collection)
    }
}

/// The presented list retains its original season while replacement details load.
/// Only playback identity follows the live store, so repeated selections keep
/// the same sheet and scroll surface alive.
struct UgcSeasonPlaybackSheet: View {
    let season: UgcSeason
    @Environment(NowPlayingStore.self) private var store

    var body: some View {
        UgcSeasonSheet(season: season, currentBvid: store.route?.bvid) { episode in
            guard episode.bvid != nil else { return }
            if episode.bvid != store.route?.bvid { store.openEpisode(episode) }
            store.requestPlayback()
        }
    }
}
