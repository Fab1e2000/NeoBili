import SwiftUI

/// 简介下方的官方相关视频推流。
///
/// 数据来自 `x/web-interface/archive/related`，是 B 站针对当前这个视频算出来的
/// 关联稿件，和首页那条按整体兴趣出内容的推荐流不是一回事。
///
/// 推荐列表直接铺在页面上，行内不重复铺底，也不播放进入动画。
struct RelatedVideosSection: View {
    /// 与上方玻璃容器外边缘对齐，只保留一层页面留白。
    private static let horizontalInset: CGFloat = 16

    let videos: [VideoSummary]
    let isLoading: Bool
    let onSelect: (VideoSummary) -> Void
    @Environment(\.hidesPortraitVideos) private var hidesPortraitVideos

    private var visibleVideos: [VideoSummary] {
        videos.hidingKnownPortraitVideos(hidesPortraitVideos)
    }

    var body: some View {
        let visibleVideos = visibleVideos
        let lastVideoID = visibleVideos.last?.id
        // Lazy 化：相关视频一次二三十条，普通 VStack 会把全部封面同时
        // 送去下载和解码，打开视频页就是一次 CPU/带宽尖峰。行的外观与
        // 分隔线逻辑保持不变。
        LazyVStack(alignment: .leading, spacing: 0) {
            if visibleVideos.isEmpty {
                if isLoading || videos.hasPendingVideoDimensions(hidesPortraitVideos) {
                    LoadingTaskAnchor()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    Text(videos.isEmpty ? "暂时没有相关视频" : "相关视频已被内容过滤设置隐藏")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(visibleVideos) { video in
                    // 相关视频自带 cid，所以点进去时和推荐页一样可以并行加载。
                    Button {
                        onSelect(video)
                    } label: {
                        VideoListCard(
                            coverURL: video.secureCoverURL,
                            title: video.title,
                            author: video.owner.name,
                            playCount: video.stat.view,
                            durationText: video.formattedDuration,
                            showsCardChrome: false,
                            animatesEntrance: false
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        WatchLaterMenuButton(aid: video.aid, bvid: video.bvid)
                    }
                    .padding(.vertical, 4)
                    // 出现在屏幕上就先把播放地址取回来，点开时通常已经有结果了。
                    .task {
                        await VideoPreparationCache.shared.prefetchWhenSettled(
                            bvid: video.bvid,
                            cid: video.cid
                        )
                    }

                    // 分隔线与推荐内容的左右边缘对齐；
                    // 最后一条不画，列表末尾不该悬着一根线。
                    if video.id != lastVideoID {
                        Divider()
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Self.horizontalInset)
        .resolvePortraitVideos(videos)
    }
}
