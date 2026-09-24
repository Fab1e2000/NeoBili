import SwiftUI

/// 把点赞观察和可见性任务限制在行内，避免牵动整个动态列表及头像条。
/// 每行仍以动态 ID 为身份，展开正文、投票和转场状态不会串到其他动态。
struct DynamicFeedCard: View {
    let entry: DynamicEntry
    let feed: DynamicFeedModel
    let lastVisibleID: String?
    let onOpenVideo: () -> Void
    let onOpenAuthor: (() -> Void)?
    let onLike: () -> Void
    let onOpenDetail: () -> Void
    var showsAuthor = true

    @Environment(\.hidesPortraitVideos) private var hidesPortraitVideos
    @State private var isVisible = false

    private struct PaginationRequest: Equatable {
        let feedID: ObjectIdentifier
        let generation: Int
        let count: Int
        let lastVisibleID: String?
    }

    var body: some View {
        let video = entry.video
        let preparationID = isVisible && (video?.canDisplayVideo(hidingPortrait: hidesPortraitVideos) ?? false)
            ? video?.bvid : nil
        let pagination = isVisible ? PaginationRequest(feedID: ObjectIdentifier(feed), generation: feed.entriesGeneration,
                                                        count: feed.entries.count, lastVisibleID: lastVisibleID) : nil
        DynamicCard(
            entry: entry,
            isLiked: feed.isLiked(entry),
            likeCount: feed.likeCount(entry),
            onOpenVideo: onOpenVideo,
            onOpenAuthor: onOpenAuthor,
            onLike: onLike,
            onOpenDetail: onOpenDetail,
            showsAuthor: showsAuthor
        )
        .onScrollVisibilityChange(threshold: 0.1) { visible in
            isVisible = visible
        }
        // LazyVStack 会提前创建屏外行，生命周期 task 并不代表用户正在看它。
        // 离开视口即取消停留等待；滑过的卡片不抢播放地址预取名额。
        .task(id: preparationID) {
            guard let preparationID else { return }
            await VideoPreparationCache.shared.prefetchWhenSettled(bvid: preparationID)
        }
        .task(id: pagination) {
            guard pagination != nil else { return }
            await feed.loadMoreIfNeeded(current: entry, lastVisibleID: lastVisibleID)
        }
    }
}
