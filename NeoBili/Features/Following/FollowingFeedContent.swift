import SwiftUI

/// Content only: the parent retains its scroll container, navigation and refresh tasks.
struct FollowingFeedContent: View {
    let feed: DynamicFeedModel
    let showsAuthor: Bool
    let hidesPortraitVideos: Bool
    let filtering: VideoFilterDependencies
    let dynamicTransition: Namespace.ID
    let onRetry: () -> Void
    let onLoadReplacement: () -> Void
    let onOpenVideo: (DynamicEntry) -> Void
    let onOpenAuthor: (DynamicEntry) -> Void
    let onLike: (DynamicEntry) -> Void
    let onOpenDetail: (DynamicEntry) -> Void

    @ViewBuilder
    var body: some View {

        if feed.isLoading, feed.entries.isEmpty {
            loadingPlaceholder
        } else if let message = feed.errorMessage, feed.entries.isEmpty {
            ContentUnavailableView {
                Label("加载失败", systemImage: "wifi.slash")
            } description: {
                Text(message)
            } actions: {
                Button("重试") {
                    onRetry()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 300)
        } else if !feed.isLoading, feed.entries.isEmpty {
            ContentUnavailableView(
                "还没有新动态",
                systemImage: "bell.slash",
                description: Text(
                    showsAuthor
                        ? "你关注的 UP 主最近没有更新。"
                        : "这位 UP 主最近没有更新。"
                )
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: 300)
        } else {
            let visibleEntries = feed.entries.filter { $0.video?.canDisplayVideo(hidingPortrait: hidesPortraitVideos, filtering: filtering) ?? true }
            if visibleEntries.isEmpty {
                if feed.entries.compactMap(\.video).hasPendingVideoDimensions(hidesPortraitVideos, filtering: filtering) {
                    LoadingTaskAnchor().padding()
                } else {
                    Button("继续加载动态") { onLoadReplacement() }
                        .padding()
                }
            }
            ForEach(visibleEntries) { entry in
                card(for: entry, lastVisibleID: visibleEntries.last?.id)
                    .videoEntranceIdentity(entry.video?.bvid)
                    .padding(.horizontal, DynamicCardLayout.pageHorizontalInset)
                    .padding(.vertical, DynamicCardLayout.cardVerticalSpacing)
            }

            if feed.isLoadingMore {
                LoadingTaskAnchor()
                    .padding()
            }
        }
    }

    private var loadingPlaceholder: some View {
        LoadingTaskAnchor()
    }

    private func card(for entry: DynamicEntry, lastVisibleID: String?) -> some View {
        DynamicFeedCard(
            entry: entry,
            feed: feed,
            lastVisibleID: lastVisibleID,
            onOpenVideo: { onOpenVideo(entry) },
            // 卡片头像和头像条的长按菜单都可以进入 UP 主页。
            onOpenAuthor: { onOpenAuthor(entry) },
            onLike: { onLike(entry) },
            onOpenDetail: { onOpenDetail(entry) },
            showsAuthor: showsAuthor
        )
        .videoTransitionSource("following-dynamic-\(entry.id)", in: dynamicTransition)
        .contextMenu {
            if let video = entry.video,
               video.canDisplayVideo(hidingPortrait: hidesPortraitVideos, filtering: filtering) {
                WatchLaterMenuButton(aid: video.aid > 0 ? video.aid : nil, bvid: video.bvid)
            }
        }
    }
}
